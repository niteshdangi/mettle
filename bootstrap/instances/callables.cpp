#include "instances/callables.h"

namespace mettle::instances {
ir::Function callableContract(Type type, const TypeStore &types) {
  const auto &signature = types.callable(type);
  ir::Function function{"<callable-contract-" + std::to_string(type.index()) +
                            ">",
                        signature.abiResult,
                        signature.parameters.size(),
                        {},
                        {},
                        0};
  function.externalName =
      "mettle.callable.contract." + std::to_string(type.index());
  function.indirectContract = true;
  function.abi = signature.abi;
  function.variadic = signature.variadic;
  function.unsafeFunction = signature.unsafeCall;
  function.targetFeatures = signature.targetFeatures;
  function.resultSources = signature.resultSources;
  for (const auto &parameter : signature.parameters)
    function.locals.push_back(
        {parameter.name, parameter.type, false, {}, parameter.mode});
  return function;
}
ir::Function callableAdapter(Type receiver, Type contract, int callee,
                             const TypeStore &types, std::string name) {
  const auto &expected = types.callable(contract);
  const auto &actual = types.callable(receiver);
  ir::Function function{std::move(name),
                        expected.abiResult,
                        expected.parameters.size() + 1,
                        {},
                        {{}},
                        0};
  function.targetFeatures = expected.targetFeatures;
  function.locals.push_back({"<callable>",
                             receiver,
                             expected.mode == ParameterMode::Take,
                             {},
                             expected.mode});
  for (const auto &parameter : expected.parameters)
    function.locals.push_back(
        {parameter.name, parameter.type, false, {}, parameter.mode});
  for (std::size_t p = 0; p < function.locals.size(); ++p)
    function.locals[p].order = static_cast<std::uint32_t>(p);
  for (auto source : expected.resultSources)
    function.resultSources.push_back(source + 1);
  auto emit = [&](ir::Instruction instruction, Type type,
                  ir::Access access = ir::Access::Owned) {
    instruction.result = {function.values++, type, access};
    auto result = instruction.result;
    function.blocks[0].instructions.push_back(std::move(instruction));
    return result;
  };
  auto forward = [&](std::size_t parameter, ParameterMode mode) {
    auto op = mode == ParameterMode::Read   ? ir::Op::BorrowRead
              : mode == ParameterMode::Mut  ? ir::Op::BorrowMut
              : mode == ParameterMode::Take ? ir::Op::Move
                                            : ir::Op::Load;
    auto access = mode == ParameterMode::Read  ? ir::Access::Read
                  : mode == ParameterMode::Mut ? ir::Access::Mut
                                               : ir::Access::Owned;
    return emit(
        {op, {}, {}, {}, "", {static_cast<int>(parameter), {}}, -1, 0, {}},
        function.locals[parameter].type, access);
  };
  bool thin = types.isFunctionPointer(receiver);
  ir::Value target;
  std::vector<ir::Value> arguments;
  if (thin)
    target = forward(0, actual.mode);
  else if (!types.product(receiver).fields.empty())
    arguments.push_back(forward(0, actual.environmentMode));
  for (std::size_t p = 0; p < expected.parameters.size(); ++p)
    arguments.push_back(forward(p + 1, expected.parameters[p].mode));
  ir::Instruction call{thin ? ir::Op::IndirectCall : ir::Op::Call,
                       {},
                       arguments,
                       {},
                       "",
                       {-1, {}},
                       callee,
                       0,
                       {}};
  call.target = target;
  call.indirectType = thin ? receiver : Type::Unknown;
  auto result = emit(std::move(call), expected.abiResult);
  if (expected.abiResult == Type::Never)
    function.blocks[0].exit.kind = ir::Exit::Unreachable;
  else {
    emit({ir::Op::ScopeExit, {}, {}, {}, "", {-1, {}}, -1, 0, {}}, Type::Unit);
    function.blocks[0].exit = {ir::Exit::Return, result};
  }
  return function;
}
} // namespace mettle::instances
