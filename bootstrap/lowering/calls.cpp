#include "lowering/builder.h"
#include <algorithm>

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
Builder::Value Builder::callExpression(const Node &node) {
  const auto &facts = module.facts(node);
  auto count = facts.constructor
                   ? node.children.size() - 1 + (facts.method ? 1 : 0)
                   : module.syntax().functions[facts.callee].parameters.size();
  if (!facts.constructor && module.syntax().functions[facts.callee].variadic)
    count = std::max(count, node.children.size() - 1);
  std::vector<Value> arguments(count);
  std::vector<std::optional<Place>> pending(count);
  DefaultFailurePaths failures;
  if (!facts.defaultArguments.empty() &&
      module.function(facts.callee).error != Type::Unknown) {
    failures.done = block();
    failures.type = facts.callResult != Type::Unknown
                        ? facts.callResult
                        : module.function(facts.callee).abiResult;
  }
  int previousExtension = extensionScope;
  if (!facts.constructor)
    extensionScope = -1;
  auto argument = [&](const Node &expression, std::size_t target, bool reserve,
                      bool receiver = false) {
    auto mode = facts.constructor ||
                        target >= module.function(facts.callee).locals.size()
                    ? ParameterMode::Value
                    : module.function(facts.callee).locals[target].mode;
    if (mode == ParameterMode::Read || mode == ParameterMode::Mut) {
      const auto &argumentFacts = module.facts(expression);
      if (argumentFacts.unsizedSource != Type::Unknown &&
          !module.typeStore()->isView(argumentFacts.type))
        return unsizedArgument(expression, mode);
      if (argumentFacts.erasedSource != Type::Unknown &&
          module.typeStore()->isErased(argumentFacts.type))
        return erasedArgument(expression, mode);
      if (receiver && facts.receiverPlan)
        return receiverBorrow(expression, *facts.receiverPlan, mode, reserve);
      if (argumentFacts.borrowConversion)
        return receiverBorrow(expression, *argumentFacts.borrowConversion,
                              mode);
      auto actual = argumentFacts.viewConversion ? argumentFacts.conversionView
                    : argumentFacts.injections.empty()
                        ? argumentFacts.type
                        : argumentFacts.injections.back();
      auto expected = facts.callParameterTypes.empty()
                          ? module.function(facts.callee).locals[target].type
                          : facts.callParameterTypes[target];
      auto dereferences = receiver ? facts.dereferences
                                   : static_cast<unsigned>(actual != expected);
      return borrow(expression, mode, reserve, false, Type::Unknown,
                    dereferences);
    }
    if (receiver &&
        (facts.receiverPlan || facts.dereferences || facts.optional)) {
      auto location = facts.receiverPlan
                          ? receiverPlace(receiverSource(expression),
                                          *facts.receiverPlan, expression.span)
                          : place(expression);
      if (!facts.receiverPlan)
        for (unsigned i = 0; i < facts.dereferences; ++i)
          location.fields.push_back(Projection::dereference());
      auto type = facts.callParameterTypes.empty()
                      ? module.function(facts.callee).locals[0].type
                      : facts.callParameterTypes[0];
      return track(
          emit({mode == ParameterMode::Take || !module.typeStore()->isCopy(type)
                    ? Op::Move
                    : Op::Load,
                {},
                {},
                {},
                "",
                location,
                -1,
                0,
                expression.span},
               type),
          expression.span);
    }
    return this->expression(expression, mode == ParameterMode::Take);
  };
  if (facts.method) {
    arguments[0] = argument(*node.children[0]->children[0], 0,
                            facts.receiverReservation, true);
    if (!live()) {
      extensionScope = previousExtension;
      return {};
    }
  }
  for (std::size_t i = 1; i < node.children.size(); ++i) {
    auto target = facts.argumentOrder[i - 1];
    arguments[target] = argument(*node.children[i], target, false);
    if (!live()) {
      extensionScope = previousExtension;
      return {};
    }
  }
  // Default thunks reborrow receiver authority after supplied arguments finish.
  bool activatedForDefaults =
      facts.receiverReservation && !facts.defaultArguments.empty();
  if (activatedForDefaults)
    emit({Op::Activate, {}, {arguments[0]}, {}, "", {-1, {}}, -1, 0, node.span},
         Type::Unit);
  for (auto parameter : facts.defaultArguments) {
    arguments[parameter] =
        defaultArgument(facts.callee, parameter, arguments, pending, failures,
                        node.span, &facts);
    if (!live()) {
      extensionScope = previousExtension;
      return {};
    }
  }
  for (std::size_t i = 0; i < arguments.size(); ++i)
    if (pending[i]) {
      owners.erase(arguments[i].id);
      arguments[i] = emit(
          {module.typeStore()->isCopy(arguments[i].type) ? Op::Load : Op::Move,
           {},
           {},
           {},
           "",
           *pending[i],
           -1,
           0,
           node.span},
          arguments[i].type);
    }
  for (auto &value : arguments)
    value = use(value);
  if (facts.receiverReservation && !activatedForDefaults)
    emit({Op::Activate, {}, {arguments[0]}, {}, "", {-1, {}}, -1, 0, node.span},
         Type::Unit);
  Instruction instruction{facts.constructor ? Op::Construct : Op::Call,
                          {},
                          arguments,
                          {},
                          "",
                          {-1, {}},
                          facts.constructor ? -1 : facts.callee,
                          0,
                          node.span};
  instruction.typeArguments = facts.typeArguments;
  if (facts.constructor &&
      module.typeStore()->product(sourceType(node)).layout.unionType)
    instruction.number = facts.field;
  instruction.interfaceType = facts.interfaceType;
  instruction.interfaceSelf = facts.interfaceSelf;
  instruction.interfaceMethod = facts.interfaceMethod;
  dynamicDispatch(instruction, facts, node.span);
  auto result = emit(std::move(instruction),
                     facts.constructor ? sourceType(node)
                     : facts.callResult != Type::Unknown
                         ? facts.callResult
                         : module.function(facts.callee).abiResult);
  extensionScope = previousExtension;
  if (result.type == Type::Never)
    terminate({Exit::Unreachable});
  if (failures.done >= 0) {
    failures.values.push_back(use(track(result, node.span)));
    failures.blocks.push_back(current);
    jump(failures.done);
    current = failures.done;
    result = merge(failures.type, failures.values, failures.blocks);
  }
  return track(result, node.span);
}
} // namespace mettle::lowering
