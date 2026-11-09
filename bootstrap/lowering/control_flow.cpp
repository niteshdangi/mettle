#include "lowering/builder.h"
#include <algorithm>

namespace mettle::lowering {
using ir::Exit;
using ir::Op;

Builder::Value Builder::loopExpression(const Node &node) {
  if (!node.patterns.empty() ||
      (node.kind == Kind::While &&
       node.children[0]->kind == Kind::ConditionChain))
    return whilePatternExpression(node);
  int header = block(), body = block(), done = block();
  loops.push_back(
      {header, done, scopes.size(), module.facts(node).control, {}, {}});
  jump(header);
  current = header;
  if (node.kind == Kind::While) {
    int savedTemporary = temporaryScope;
    temporaryScope = scope();
    auto condition = use(expression(*node.children[0]));
    endScope(node.children[0]->span);
    temporaryScope = savedTemporary;
    branch(*node.children[0], condition, body, done);
  } else
    jump(body);
  current = body;
  if (node.kind == Kind::While &&
      (!module.facts(*node.children[0]).flow.normal ||
       booleanLiteral(*node.children[0]) == false))
    terminate({Exit::Unreachable});
  blockExpression(*node.children.back(), false);
  auto loop = std::move(loops.back());
  loops.pop_back();
  jump(header);
  current = done;
  if (!module.facts(node).flow.normal) {
    terminate({Exit::Unreachable});
    return {};
  }
  if (node.kind == Kind::While)
    return unit();
  return track(merge(sourceType(node), loop.values, loop.predecessors),
               node.span);
}

Builder::Value Builder::transferExpression(const Node &node) {
  auto found =
      std::find_if(loops.rbegin(), loops.rend(), [&](const auto &loop) {
        return loop.control == module.facts(node).control;
      });
  if (found == loops.rend())
    throw std::runtime_error("checked loop target is not active");
  auto index =
      static_cast<std::size_t>(std::distance(loops.begin(), found.base()) - 1);
  auto depth = loops[index].depth;
  if (node.kind == Kind::Continue) {
    exitTo(depth, node.span);
    jump(loops[index].header);
    return {};
  }
  auto value = node.children.empty() ? unit() : expression(*node.children[0]);
  if (!live())
    return {};
  std::optional<Place> pending;
  if (module.typeStore()->needsDrop(value.type))
    pending = materialize(value, node.span, -2);
  exitTo(depth, node.span);
  value = pending ? emit({Op::Move, {}, {}, {}, "", *pending, -1, 0, node.span},
                         value.type)
                  : use(value);
  loops[index].values.push_back(value);
  loops[index].predecessors.push_back(current);
  jump(loops[index].done);
  return {};
}
} // namespace mettle::lowering
