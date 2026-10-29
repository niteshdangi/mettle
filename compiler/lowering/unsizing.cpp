#include "lowering/builder.h"

namespace mettle::lowering {
Builder::Value Builder::viewCoercion(const Node &node) {
  if (!live())
    return {};
  const auto &facts = module.facts(node);
  auto sourceType = facts.unsizedSource != Type::Unknown ? facts.unsizedSource
                    : facts.erasedSource != Type::Unknown
                        ? facts.erasedSource
                        : facts.reborrowSource;
  Place source;
  bool located = node.kind == Kind::Name || node.kind == Kind::Field ||
                 node.kind == Kind::Index || node.kind == Kind::Group ||
                 (node.kind == Kind::Unary && node.text == "*");
  if (located)
    source = place(
        node, true,
        module.typeStore()->view(facts.type).mode == ParameterMode::Mut, false);
  else {
    auto value = rawExpression(node, false, true);
    if (!live())
      return {};
    source = materialize(value, node.span,
                         extensionScope >= 0 ? extensionScope : temporaryScope);
  }
  source.fields.push_back(Projection::dereference());
  source = capturePlace(std::move(source));
  if (facts.unsizedSource != Type::Unknown)
    return unsizedView(std::move(source), facts.type, facts.unsizedCount,
                       node.span);
  if (facts.erasedSource != Type::Unknown)
    return erasedView(std::move(source),
                      module.typeStore()->view(sourceType).payload, facts.type,
                      node.span);
  return emit(
      {ir::Op::ViewRead, {}, {}, {}, "", std::move(source), -1, 0, node.span},
      facts.type);
}
Builder::Value Builder::unsizedView(Place source, Type view, Type count,
                                    Span span) {
  Instruction length{ir::Op::Constant, {}, {}, {}, "", {-1, {}}, -1, 0, span};
  length.constantParameter = count;
  auto size = emit(std::move(length), Type::I32);
  return emit(
      {ir::Op::UnsizeView, {}, {size}, {}, "", std::move(source), -1, 0, span},
      view);
}
Builder::Value Builder::unsizedArgument(const Node &node, ParameterMode mode) {
  const auto &facts = module.facts(node);
  auto source = place(node, false, mode == ParameterMode::Mut, false);
  auto type = facts.unsizedSource;
  while (module.typeStore()->isView(type)) {
    source.fields.push_back(Projection::dereference());
    type = module.typeStore()->view(type).payload;
  }
  source = capturePlace(std::move(source));
  auto view = mode == ParameterMode::Read ? facts.readView : facts.mutView;
  auto value =
      unsizedView(std::move(source), view, facts.unsizedCount, node.span);
  auto stored = materialize(value, node.span, temporaryScope);
  stored.fields.push_back(Projection::dereference());
  return emit(
      {mode == ParameterMode::Read ? ir::Op::BorrowRead : ir::Op::BorrowMut,
       {},
       {},
       {},
       "",
       std::move(stored),
       -1,
       0,
       node.span},
      facts.type,
      mode == ParameterMode::Read ? ir::Access::Read : ir::Access::Mut);
}
} // namespace mettle::lowering
