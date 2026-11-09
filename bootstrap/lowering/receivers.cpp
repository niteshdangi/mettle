#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Access;
using ir::Op;
Place Builder::capturePlace(Place source) const {
  for (const auto &[proxy, target] : capturedPlaces)
    if (containsPlace(proxy, source)) {
      auto result = target;
      result.fields.insert(result.fields.end(),
                           source.fields.begin() + proxy.fields.size(),
                           source.fields.end());
      return result;
    }
  return source;
}
bool Builder::callHasFailure(const Node &node) const {
  const auto &facts = module.facts(node);
  if (facts.indirect) {
    auto type = module.facts(*node.children[0]).type;
    while (module.typeStore()->isView(type))
      type = module.typeStore()->view(type).payload;
    return module.typeStore()->callable(type).error != Type::Unknown;
  }
  return facts.callee >= 0 &&
         !module.syntax().functions[facts.callee].error.empty();
}
Place Builder::receiverSource(const Node &node, bool extend) {
  if (module.facts(node).place || node.kind == Kind::Name ||
      node.kind == Kind::Field || node.kind == Kind::Index ||
      node.kind == Kind::Group ||
      (node.kind == Kind::Unary && node.text == "*"))
    return place(node, extend, false, false);
  auto value = rawExpression(node, false, true);
  const auto &facts = module.facts(node);
  if (live() && (node.kind == Kind::Call || facts.operatorCall) &&
      facts.effect != Type::Unknown && !facts.optional && callHasFailure(node))
    value = unwrapOutcome(value, node.span);
  if (!live())
    return {-1, {}};
  return materialize(value, node.span,
                     extend && extensionScope >= 0 ? extensionScope
                                                   : temporaryScope);
}
Place Builder::receiverPlace(Place source, const ReceiverPlan &plan,
                             Span span) {
  for (const auto &step : plan.steps) {
    if (step.kind == ReceiverStep::Kind::Native) {
      source.fields.push_back(Projection::dereference());
      source = capturePlace(std::move(source));
      continue;
    }
    if (step.kind == ReceiverStep::Kind::Unsize) {
      auto value =
          unsizedView(std::move(source), step.resultView, step.count, span);
      source = materialize(value, span, temporaryScope);
      source.fields.push_back(Projection::dereference());
      continue;
    }
    if (step.kind == ReceiverStep::Kind::Erase) {
      auto value =
          erasedView(std::move(source), step.source, step.resultView, span);
      source = materialize(value, span, temporaryScope);
      source.fields.push_back(Projection::dereference());
      continue;
    }
    auto argument =
        emit({step.mode == ParameterMode::Mut ? Op::BorrowMut : Op::BorrowRead,
              {},
              {},
              {},
              "",
              source,
              -1,
              0,
              span},
             step.source,
             step.mode == ParameterMode::Mut ? Access::Mut : Access::Read);
    Instruction call{Op::Call, {},          {argument}, {},  "",
                     {-1, {}}, step.callee, 0,          span};
    call.typeArguments = step.typeArguments;
    call.interfaceSelf = step.interfaceSelf;
    call.interfaceType = step.interfaceType;
    call.interfaceMethod = step.interfaceMethod;
    NodeFacts dispatch;
    dispatch.interfaceSelf = step.interfaceSelf;
    dispatch.interfaceType = step.interfaceType;
    dispatch.interfaceMethod = step.interfaceMethod;
    dynamicDispatch(call, dispatch, span);
    auto value = emit(std::move(call), step.resultView);
    source = materialize(value, span, temporaryScope);
    source.fields.push_back(Projection::dereference());
  }
  return source;
}
Builder::Value Builder::receiverBorrow(const Node &node,
                                       const ReceiverPlan &plan,
                                       ParameterMode mode, bool reserved,
                                       Type view) {
  auto source = receiverSource(node, view != Type::Unknown);
  if (!live())
    return {};
  source = receiverPlace(std::move(source), plan, node.span);
  if (!live())
    return {};
  auto op = view != Type::Unknown
                ? (mode == ParameterMode::Mut ? Op::ViewMut : Op::ViewRead)
            : mode == ParameterMode::Read ? Op::BorrowRead
            : reserved                    ? Op::ReserveMut
                                          : Op::BorrowMut;
  return emit({op, {}, {}, {}, "", std::move(source), -1, 0, node.span},
              view == Type::Unknown ? plan.target : view,
              view != Type::Unknown         ? Access::Owned
              : mode == ParameterMode::Read ? Access::Read
                                            : Access::Mut);
}
Builder::Value Builder::convertedView(const Node &node) {
  const auto &facts = module.facts(node);
  return receiverBorrow(node, *facts.viewConversion,
                        module.typeStore()->view(facts.conversionView).mode,
                        false, facts.conversionView);
}
} // namespace mettle::lowering
