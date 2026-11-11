#include "lowering/builder.h"
#include <algorithm>

namespace mettle::lowering {
Builder::Value Builder::operatorExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto argument = [&](std::size_t index) {
    const auto &source = *node.children[index];
    auto mode = module.function(facts.callee).locals[index].mode;
    // A view-typed operand (`s += "!"` with `Rhs = read Text`) is borrowed
    // as a view value, not through to its payload.
    if (index > 0 && mode == ParameterMode::Read &&
        module.typeStore()->isView(facts.callParameterTypes[index]) &&
        module.typeStore()->isView(module.facts(source).type) &&
        module.typeStore()->view(module.facts(source).type).payload ==
            module.typeStore()->view(facts.callParameterTypes[index]).payload) {
      auto value = use(expression(source));
      if (!live())
        return Value{};
      auto location = materialize(value, source.span, temporaryScope);
      return emit(
          {ir::Op::BorrowRead, {}, {}, {}, "", location, -1, 0, source.span},
          value.type, ir::Access::Read);
    }
    if (mode == ParameterMode::Read || mode == ParameterMode::Mut) {
      auto dereferences =
          index == 0 ? facts.dereferences
                     : static_cast<unsigned>(module.facts(source).type !=
                                             facts.callParameterTypes[index]);
      return borrow(source, mode, index == 0 && facts.receiverReservation,
                    false, Type::Unknown, dereferences);
    }
    return expression(source, mode == ParameterMode::Take);
  };
  const bool ranged =
      node.kind == Kind::Index && node.children[1]->kind == Kind::Range;
  std::vector<Value> arguments(ranged ? 3 : node.children.size());
  if (ranged && live()) {
    // Evaluate the base and bounds in source order.
    const auto &range = *node.children[1];
    const bool hasStart = range.name.empty() || range.name == "from";
    const bool hasEnd = range.name.empty() || range.name == "to";
    arguments[0] = argument(0);
    if (!live())
      return {};
    auto synthesized = [&](Value value, std::size_t index) {
      auto mode = module.function(facts.callee).locals[index].mode;
      if (mode != ParameterMode::Read && mode != ParameterMode::Mut)
        return value;
      auto storage = materialize(value, node.span, temporaryScope);
      return emit(
          {mode == ParameterMode::Read ? ir::Op::BorrowRead : ir::Op::BorrowMut,
           {},
           {},
           {},
           "",
           storage,
           -1,
           0,
           node.span},
          value.type,
          mode == ParameterMode::Read ? ir::Access::Read : ir::Access::Mut);
    };
    auto startMode = module.function(facts.callee).locals[1].mode;
    if (hasStart &&
        (startMode == ParameterMode::Read || startMode == ParameterMode::Mut)) {
      const auto &start = *range.children.front();
      arguments[1] = borrow(start, startMode, false, false, Type::Unknown,
                            static_cast<unsigned>(module.facts(start).type !=
                                                  facts.callParameterTypes[1]));
    } else if (hasStart)
      arguments[1] = use(expression(*range.children.front(),
                                    startMode == ParameterMode::Take));
    else
      arguments[1] = synthesized(constant(Type::Usize, 0), 1);
    if (live()) {
      auto type = facts.callParameterTypes[2];
      const auto &variants = module.typeStore()->product(type).variants;
      const auto name = !hasEnd               ? "Unbounded"
                        : range.text == "..=" ? "Inclusive"
                                              : "Exclusive";
      auto found =
          std::find_if(variants.begin(), variants.end(),
                       [&](const auto &item) { return item.name == name; });
      auto tag = static_cast<int>(found - variants.begin());
      if (hasEnd) {
        auto value = use(expression(*range.children.back()));
        if (live())
          arguments[2] = synthesized(variant(type, tag, {value}, node.span), 2);
      } else {
        arguments[2] = synthesized(variant(type, tag, {}, node.span), 2);
      }
    }
  } else {
    for (std::size_t i = 0; i < arguments.size() && live(); ++i)
      arguments[i] = argument(i);
  }
  if (!live())
    return {};
  for (auto &value : arguments)
    value = use(value);
  if (facts.receiverReservation)
    emit({ir::Op::Activate,
          {},
          {arguments[0]},
          {},
          "",
          {-1, {}},
          -1,
          0,
          node.span},
         Type::Unit);
  Instruction call{ir::Op::Call, {}, std::move(arguments),
                   {},           "", {-1, {}},
                   facts.callee, 0,  node.span};
  call.interfaceSelf = facts.interfaceSelf;
  call.interfaceType = facts.interfaceType;
  call.interfaceMethod = facts.interfaceMethod;
  call.typeArguments = facts.typeArguments;
  dynamicDispatch(call, facts, node.span);
  auto result = emit(std::move(call), facts.callResult);
  if (result.type == Type::Never)
    terminate({ir::Exit::Unreachable});
  return track(result, node.span);
}
} // namespace mettle::lowering
