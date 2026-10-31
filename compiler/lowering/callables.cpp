#include "lowering/builder.h"
#include <algorithm>
#include <tuple>

namespace mettle::lowering {
using ir::Access;
using ir::Exit;
using ir::Op;
void callableContracts(ir::Program &program) {
  auto key = [&](const ir::Instruction &instruction) {
    const auto &signature = program.types->callable(instruction.indirectType);
    bool twoPhase = instruction.erasedDispatch &&
                    !signature.parameters.empty() &&
                    signature.parameters[0].mode == ParameterMode::Mut;
    return std::tuple{instruction.indirectType, twoPhase,
                      instruction.callLocalParameters};
  };
  std::map<std::tuple<Type, bool, std::vector<std::size_t>>, int> contracts;
  for (const auto &function : program.functions)
    for (const auto &block : function.blocks)
      for (const auto &instruction : block.instructions)
        if (instruction.op == Op::IndirectCall)
          contracts.try_emplace(key(instruction), -1);
  auto ordinary = program.functions.size();
  for (auto &[identity, index] : contracts) {
    const auto &[type, twoPhase, local] = identity;
    const auto &signature = program.types->callable(type);
    auto suffix = twoPhase ? ".two-phase" : "";
    ir::Function contract{"<indirect-" + std::to_string(type.index()) + suffix +
                              ">",
                          signature.abiResult,
                          signature.parameters.size(),
                          {},
                          {},
                          0};
    contract.externalName =
        "mettle.indirect." + std::to_string(type.index()) + suffix;
    contract.indirectContract = true;
    contract.abi = signature.abi;
    contract.variadic = signature.variadic;
    contract.unsafeFunction = signature.unsafeCall;
    contract.targetFeatures = signature.targetFeatures;
    contract.twoPhaseReceiver = twoPhase;
    contract.resultSources = signature.resultSources;
    contract.callLocalParameters = local;
    contract.genericParameters = program.types->typeParameters(type);
    for (const auto &parameter : signature.parameters)
      contract.locals.push_back(
          {parameter.name, parameter.type, false, {}, parameter.mode});
    index = static_cast<int>(program.functions.size());
    program.functions.push_back(std::move(contract));
  }
  for (std::size_t f = 0; f < ordinary; ++f)
    for (auto &block : program.functions[f].blocks)
      for (auto &instruction : block.instructions)
        if (instruction.op == Op::IndirectCall) {
          instruction.callee = contracts.at(key(instruction));
          instruction.typeArguments =
              program.functions[instruction.callee].genericParameters;
        }
}
int Builder::closureIndex(std::size_t index) const {
  auto result = module.syntax().functions.size();
  for (const auto &function : module.syntax().functions)
    for (const auto &parameter : function.parameters)
      result += parameter.defaultValue.get() != nullptr;
  return static_cast<int>(result + index);
}
std::vector<Type> Builder::closureArguments(Type type) const {
  const auto &environment = module.typeStore()->product(type);
  if (environment.genericOrigin != Type::Unknown)
    return environment.genericArguments;
  return module.closures()
      .at(module.typeStore()->callable(type).function)
      ->function.genericParameters;
}
ir::Function Builder::runClosure(std::size_t index) {
  const auto &closure = *module.closures().at(index);
  const auto &checked = closure.function;
  bool environment = !closure.captures.empty();
  function = {checked.canonicalName,
              checked.abiResult,
              closure.declaration.parameters.size() + environment,
              {},
              {},
              0};
  errorType = checked.error;
  function.genericParameters = checked.genericParameters;
  function.targetFeatures = checked.targetFeatures;
  function.interfaceBounds = checked.interfaceBounds;
  function.unpinBounds = checked.unpinBounds;
  function.regionSignature = checked.regionSignature;
  function.genericEqualities = checked.genericEqualities;
  function.floatingPolicy = checked.floatingPolicy;
  function.span = closure.syntax->span;
  function.coroutine = closure.syntax->text == "coroutine";
  for (std::size_t i = environment ? 0 : 1; i < checked.locals.size(); ++i) {
    const auto &local = checked.locals[i];
    localRemap[static_cast<int>(i)] = static_cast<int>(function.locals.size());
    function.locals.push_back({local.name, local.type, local.mutableBinding,
                               local.span, local.mode, 0, 0, local.storage,
                               local.staticIndex});
    if (i >= closure.declaration.parameters.size() + 1)
      function.locals.back().mode = ParameterMode::Value;
  }
  for (auto source : checked.resultSources)
    function.resultSources.push_back(source - !environment);
  for (std::size_t i = 0; i < function.locals.size(); ++i) {
    function.locals[i].scope = i < function.parameters ? 0 : -1;
    function.locals[i].order =
        i < function.parameters ? static_cast<std::uint32_t>(i) : 0;
  }
  order = static_cast<std::uint32_t>(function.parameters);
  for (std::size_t i = 0; i < closure.captures.size(); ++i) {
    const auto &capture = closure.captures[i];
    Place target{0, {Projection::field(static_cast<std::uint32_t>(i))}};
    if (!closure.syntax->flag)
      target.fields.push_back(Projection::dereference());
    capturedPlaces.emplace_back(capture.proxy, std::move(target));
  }
  current = block();
  for (std::size_t p = 0; p < closure.declaration.parameters.size(); ++p)
    if (closure.syntax->parameters[p].pattern)
      patternBind(*closure.syntax->parameters[p].pattern,
                  {localSlot(static_cast<int>(p + 1)), {}},
                  checked.locals[p + 1].mode);
  auto result = expression(*closure.syntax->children[0]);
  if (live()) {
    if (module.facts(*closure.syntax->children[0]).flow.normal)
      returnValue(result, closure.syntax->span);
    else
      terminate({Exit::Unreachable});
  }
  for (auto &block : function.blocks)
    if (block.exit.kind == Exit::None)
      block.exit.kind = Exit::Unreachable;
  return std::move(function);
}
Builder::Value Builder::callableExpression(const Node &node) {
  const auto &facts = module.facts(node);
  if (node.kind == Kind::Name || facts.callableCoercion != Type::Unknown) {
    auto callee = node.kind == Kind::Name
                      ? facts.callee
                      : closureIndex(static_cast<std::size_t>(facts.closure));
    Instruction instruction{
        Op::FunctionAddress, {}, {}, {}, "", {-1, {}}, callee, 0, node.span};
    instruction.typeArguments =
        node.kind == Kind::Name
            ? facts.typeArguments
            : module.closures().at(facts.closure)->function.genericParameters;
    return emit(std::move(instruction), facts.callableCoercion == Type::Unknown
                                            ? sourceType(node)
                                            : facts.callableCoercion);
  }
  const auto &closure = *module.closures().at(facts.closure);
  std::vector<Value> captures;
  for (const auto &capture : closure.captures) {
    auto source = capture.source;
    bool mapped = false;
    for (const auto &[proxy, target] : capturedPlaces)
      if (containsPlace(proxy, source)) {
        Place projected = target;
        projected.fields.insert(projected.fields.end(),
                                source.fields.begin() + proxy.fields.size(),
                                source.fields.end());
        source = std::move(projected);
        mapped = true;
        break;
      }
    if (!mapped)
      source.root = localSlot(source.root);
    auto op = node.flag ? (capture.mode == ParameterMode::Take ||
                                   !module.typeStore()->isCopy(capture.type)
                               ? Op::Move
                               : Op::Load)
              : capture.mode == ParameterMode::Mut ? Op::ViewMut
                                                   : Op::ViewRead;
    captures.push_back(emit({op, {}, {}, {}, "", source, -1, 0, capture.span},
                            capture.storedType));
  }
  return track(
      emit({Op::Construct, {}, captures, {}, "", {-1, {}}, -1, 0, node.span},
           closure.type),
      node.span);
}
Builder::Value Builder::indirectCallExpression(const Node &node) {
  const auto &facts = module.facts(node);
  const auto &callee = *node.children[0];
  auto type = module.facts(callee).type;
  while (module.typeStore()->isView(type))
    type = module.typeStore()->view(type).payload;
  const auto signature = module.typeStore()->callable(type);
  bool abstract = module.typeStore()->isParameter(type);
  bool thin = module.typeStore()->isFunctionPointer(type) || abstract;
  std::vector<Value> arguments;
  Value target;
  if (thin) {
    if (signature.mode == ParameterMode::Read ||
        signature.mode == ParameterMode::Mut)
      target = borrow(callee, signature.mode, false, false, Type::Unknown,
                      facts.dereferences);
    else if (facts.dereferences) {
      auto location = place(callee);
      for (unsigned i = 0; i < facts.dereferences; ++i)
        location.fields.push_back(Projection::dereference());
      target =
          emit({Op::Move, {}, {}, {}, "", location, -1, 0, callee.span}, type);
    } else
      target = use(expression(callee, signature.mode == ParameterMode::Take));
  } else {
    const auto &closure =
        *module.closures().at(module.facts(callee).closure >= 0
                                  ? module.facts(callee).closure
                                  : static_cast<int>(signature.function));
    if (!closure.captures.empty()) {
      if (signature.environmentMode == ParameterMode::Value)
        arguments.push_back(use(expression(callee)));
      else if (signature.mode == ParameterMode::Read ||
               signature.mode == ParameterMode::Mut)
        arguments.push_back(borrow(callee, signature.mode, false, false,
                                   Type::Unknown, facts.dereferences));
      else if (facts.dereferences) {
        auto location = place(callee);
        for (unsigned i = 0; i < facts.dereferences; ++i)
          location.fields.push_back(Projection::dereference());
        arguments.push_back(emit(
            {Op::Move, {}, {}, {}, "", location, -1, 0, callee.span}, type));
      } else
        arguments.push_back(use(expression(callee, true)));
    } else
      expression(callee, signature.mode == ParameterMode::Take);
  }
  if (!live())
    return {};
  auto savedExtension = extensionScope;
  extensionScope = -1;
  for (std::size_t i = 1; i < node.children.size(); ++i) {
    const auto &argument = *node.children[i];
    auto formal = i - 1 < signature.parameters.size()
                      ? signature.parameters[i - 1]
                      : CallableParameter{module.facts(argument).type,
                                          ParameterMode::Value};
    Value value;
    if (formal.mode == ParameterMode::Read ||
        formal.mode == ParameterMode::Mut) {
      const auto &argumentFacts = module.facts(argument);
      if (argumentFacts.unsizedSource != Type::Unknown &&
          !module.typeStore()->isView(argumentFacts.type)) {
        value = unsizedArgument(argument, formal.mode);
        arguments.push_back(use(value));
        continue;
      }
      if (argumentFacts.erasedSource != Type::Unknown &&
          module.typeStore()->isErased(argumentFacts.type)) {
        value = erasedArgument(argument, formal.mode);
        arguments.push_back(use(value));
        continue;
      }
      if (module.facts(argument).borrowConversion) {
        value = receiverBorrow(
            argument, *module.facts(argument).borrowConversion, formal.mode);
        if (!live()) {
          extensionScope = savedExtension;
          return {};
        }
        arguments.push_back(use(value));
        continue;
      }
      auto actual = module.facts(argument).viewConversion
                        ? module.facts(argument).conversionView
                        : module.facts(argument).type;
      if (!module.facts(argument).injections.empty())
        actual = module.facts(argument).injections.back();
      value = borrow(argument, formal.mode, false, false, Type::Unknown,
                     static_cast<unsigned>(actual != formal.type));
    } else
      value = expression(argument, formal.mode == ParameterMode::Take);
    if (!live()) {
      extensionScope = savedExtension;
      return {};
    }
    arguments.push_back(use(value));
  }
  extensionScope = savedExtension;
  Instruction instruction{
      thin ? Op::IndirectCall : Op::Call,
      {},
      arguments,
      {},
      "",
      {-1, {}},
      thin ? -1 : closureIndex(static_cast<std::size_t>(signature.function)),
      0,
      node.span};
  instruction.target = target;
  instruction.indirectType =
      abstract ? module.typeStore()->parameter(type).callableConstraint
      : thin   ? type
               : Type::Unknown;
  if (abstract)
    instruction.callLocalParameters =
        module.typeStore()->parameter(type).callableLocalParameters;
  if (!thin)
    instruction.typeArguments = closureArguments(type);
  auto value = emit(std::move(instruction), signature.abiResult);
  if (value.type == Type::Never)
    terminate({Exit::Unreachable});
  return track(value, node.span);
}
} // namespace mettle::lowering
