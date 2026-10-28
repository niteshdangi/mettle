#include "semantics/checker.h"
#include "support/limits.h"

namespace mettle {
Flow combine(Flow a, Flow b) {
  if (!a.normal)
    return a;
  return {b.normal, a.returns || b.returns, a.breaks || b.breaks,
          a.continues || b.continues};
}
Flow branches(Flow a, Flow b) {
  return {a.normal || b.normal, a.returns || b.returns, a.breaks || b.breaks,
          a.continues || b.continues};
}
Flow Checker::flow(Node &n) {
  Flow result;
  if (n.kind == Kind::Block) {
    for (auto &child : n.children)
      result = combine(result, flow(*child));
  } else if (n.kind == Kind::If) {
    result = flow(*n.children[0]);
    auto a = flow(*n.children[1]);
    auto b = n.children.size() == 3 ? flow(*n.children[2]) : Flow{};
    if (auto literal = booleanLiteral(*n.children[0]))
      result = combine(result, *literal ? a : b);
    else
      result = combine(result, branches(a, b));
  } else if (n.kind == Kind::Loop || n.kind == Kind::While) {
    Flow condition;
    if (n.kind == Kind::While)
      condition = flow(*n.children[0]);
    auto body = flow(*n.children.back());
    bool forever =
        n.kind == Kind::Loop || booleanLiteral(*n.children[0]) == true;
    bool skipped =
        n.kind == Kind::While && booleanLiteral(*n.children[0]) == false;
    result = combine(condition, {forever ? body.breaks : true,
                                 !skipped && body.returns, false, false});
  } else if (n.kind == Kind::Break) {
    result = {false, false, true, false};
  } else if (n.kind == Kind::Continue) {
    result = {false, false, false, true};
  } else if (n.kind == Kind::Return) {
    if (!n.children.empty())
      result = flow(*n.children[0]);
    if (result.normal) {
      result.normal = false;
      result.returns = true;
    }
  } else {
    for (std::size_t i = 0; i < n.children.size(); ++i) {
      auto child = flow(*n.children[i]);
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
    if (n.kind == Kind::Call && n.children[0]->kind == Kind::Name) {
      auto found = names.find(n.children[0]->text);
      if (found != names.end() &&
          facts(module.functions[found->second]).diverges)
        result.normal = false;
    }
  }
  facts(n).flow = result;
  return result;
}
} // namespace mettle
