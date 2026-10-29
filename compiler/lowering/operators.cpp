#include "lowering/builder.h"

namespace mettle::lowering {
Builder::Value Builder::operatorExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto argument = [&](std::size_t index) {
    const auto &source = *node.children[index];
    auto mode = module.function(facts.callee).locals[index].mode;
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
  std::vector<Value> arguments(node.children.size());
  for (std::size_t i = 0; i < arguments.size() && live(); ++i)
    arguments[i] = argument(i);
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
