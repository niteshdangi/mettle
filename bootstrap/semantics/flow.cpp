#include "semantics/checker.h"
#include "support/limits.h"

namespace mettle {
Flow combine(Flow a, Flow b) {
  if (!a.normal)
    return a;
  b.returns |= a.returns;
  b.breaks.insert(a.breaks.begin(), a.breaks.end());
  b.continues.insert(a.continues.begin(), a.continues.end());
  return b;
}
Flow branches(Flow a, Flow b) {
  b.normal |= a.normal;
  b.returns |= a.returns;
  b.breaks.insert(a.breaks.begin(), a.breaks.end());
  b.continues.insert(a.continues.begin(), a.continues.end());
  return b;
}
Flow Checker::flow(Node &n, std::string_view owner) {
  Flow result;
  if (n.kind == Kind::Assembly) {
    for (const auto &operand : n.assembly->operands) {
      if (operand.mode != "sym" && operand.input >= 0)
        result = combine(result, flow(*n.children[operand.input], owner));
      if (operand.output >= 0 && operand.output != operand.input)
        result = combine(result, flow(*n.children[operand.output], owner));
    }
    if (n.assembly->variant == "naked_asm" ||
        std::find(n.assembly->options.begin(), n.assembly->options.end(),
                  "noreturn") != n.assembly->options.end())
      result.normal = false;
  } else if (n.kind == Kind::ConditionChain) {
    bool canSkip = false, active = true;
    for (auto &condition : n.children) {
      auto child = flow(*condition, owner);
      if (!active)
        continue;
      result = combine(result, canSkip ? branches({}, child) : child);
      auto literal = booleanLiteral(*condition);
      active &= literal != false;
      canSkip |= literal != true;
    }
  } else if (n.kind == Kind::Closure) {
    flow(*n.children[0], owner);
  } else if (n.kind == Kind::Block) {
    for (auto &child : n.children)
      result = combine(result, flow(*child, owner));
  } else if (n.kind == Kind::Capture) {
    result = flow(*n.children[0], owner);
    result.normal = true;
  } else if (n.kind == Kind::Binding && !n.patterns.empty()) {
    result = flow(*n.children[0], owner);
    if (n.children.size() > 1)
      result = combine(result, branches({}, flow(*n.children[1], owner)));
  } else if (n.kind == Kind::Match) {
    auto input = flow(*n.children[0], owner);
    Flow arms{false, false, {}, {}};
    for (std::size_t i = 1; i < n.children.size(); ++i)
      arms = branches(arms, flow(*n.children[i], owner));
    result = combine(input, arms);
  } else if (n.kind == Kind::Throw) {
    result = flow(*n.children[0], owner);
    result.normal = false;
  } else if (n.kind == Kind::For) {
    auto input = flow(*n.children[0], owner);
    auto body = flow(*n.children[1], owner);
    body.normal = true;
    body.breaks.erase(facts(n).control);
    body.continues.erase(facts(n).control);
    result = combine(input, body);
  } else if (n.kind == Kind::If) {
    result = flow(*n.children[0], owner);
    auto a = flow(*n.children[1], owner);
    auto b = n.children.size() == 3 ? flow(*n.children[2], owner) : Flow{};
    if (auto literal = booleanLiteral(*n.children[0]))
      result = combine(result, *literal ? a : b);
    else
      result = combine(result, branches(a, b));
  } else if (n.kind == Kind::Loop || n.kind == Kind::While) {
    Flow condition;
    if (n.kind == Kind::While)
      condition = flow(*n.children[0], owner);
    auto body = flow(*n.children.back(), owner);
    bool forever =
        n.kind == Kind::Loop || booleanLiteral(*n.children[0]) == true;
    bool skipped =
        n.kind == Kind::While && booleanLiteral(*n.children[0]) == false;
    int target = facts(n).control;
    bool conditionBreak = condition.breaks.contains(target);
    bool bodyBreak = body.breaks.contains(target);
    result = condition;
    if (condition.normal && !skipped)
      result = branches(condition, body);
    result.normal =
        conditionBreak || (condition.normal && (!forever || bodyBreak));
    result.breaks.erase(target);
    result.continues.erase(target);
  } else if (n.kind == Kind::Break || n.kind == Kind::Continue) {
    if (!n.children.empty())
      result = flow(*n.children[0], owner);
    if (result.normal) {
      result.normal = false;
      auto &targets = n.kind == Kind::Break ? result.breaks : result.continues;
      targets.insert(facts(n).control);
    }
  } else if (n.kind == Kind::Return) {
    if (!n.children.empty())
      result = flow(*n.children[0], owner);
    if (result.normal) {
      result.normal = false;
      result.returns = true;
    }
  } else {
    for (std::size_t i = 0; i < n.children.size(); ++i) {
      auto child = flow(*n.children[i], owner);
      if (n.kind == Kind::Binary && i == 1 &&
          (n.text == "&&" || n.text == "||")) {
        auto literal = booleanLiteral(*n.children[0]);
        if ((n.text == "&&" && literal == false) ||
            (n.text == "||" && literal == true))
          child = {};
        else if (!literal)
          child = branches({}, child);
      }
      result = combine(result, child);
    }
    if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name &&
        !facts(*n.children[0]).lexicallyBound) {
      auto found = names.find(callableName(n.children[0]->text, owner, n.span));
      if (found != names.end() &&
          facts(module.functions[found->second]).diverges)
        result.normal = false;
    }
  }
  facts(n).flow = result;
  return result;
}
} // namespace mettle
