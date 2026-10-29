#include "semantics/checker.h"
#include <functional>

namespace mettle {
void Checker::controlFlow(Function &function) {
  std::vector<Node *> targets;
  int next = 0;
  std::function<void(Node &)> visit = [&](Node &node) {
    if (node.kind == Kind::Closure) {
      auto saved = std::move(targets);
      targets.clear();
      visit(*node.children[0]);
      targets = std::move(saved);
      return;
    }
    bool loop = node.kind == Kind::Loop || node.kind == Kind::While ||
                node.kind == Kind::For;
    if (loop) {
      facts(node).control = next++;
      targets.push_back(&node);
    } else if (node.kind == Kind::Break || node.kind == Kind::Continue) {
      auto target = targets.rbegin();
      while (target != targets.rend() && !node.label.empty() &&
             (*target)->label != node.label)
        ++target;
      if (target == targets.rend())
        error(node.label.empty() ? "type" : "name", node.span,
              node.label.empty() ? "loop control outside a loop"
                                 : "unknown loop label '" + node.label + "'");
      else
        facts(node).control = facts(**target).control;
    }
    for (auto &child : node.children)
      visit(*child);
    if (loop)
      targets.pop_back();
  };
  for (auto &parameter : function.parameters)
    if (parameter.defaultValue.get())
      visit(*parameter.defaultValue);
  visit(*function.body);
}

int Checker::loop(Node &n, bool reachable) {
  int result =
      inference.fresh(n.kind == Kind::While ? Type::Unit : Type::Unknown);
  loopResults[facts(n).control] = result;
  scopes.emplace_back();
  if (n.kind == Kind::While) {
    auto condition = node(*n.children[0], reachable);
    if (n.patterns.empty())
      inference.equal(condition, inference.fresh(Type::Bool), n.span, true);
    else
      pattern(n.patterns[0], condition, ParameterMode::Read);
  }
  node(*n.children.back(),
       reachable &&
           (n.kind != Kind::While || facts(*n.children[0]).flow.normal) &&
           !(n.kind == Kind::While && booleanLiteral(*n.children[0]) == false));
  scopes.pop_back();
  return facts(n).flow.normal ? result : inference.fresh(Type::Never);
}

int Checker::transfer(Node &n, bool reachable) {
  if (n.kind == Kind::Break) {
    int value = n.children.empty() ? inference.fresh(Type::Unit)
                                   : node(*n.children[0], reachable);
    inference.equal(value, loopResults.at(facts(n).control), n.span, true);
  }
  return inference.fresh(Type::Never);
}
} // namespace mettle
