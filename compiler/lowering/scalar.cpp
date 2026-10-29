#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
ir::Function Builder::run(const mettle::Function &source, std::size_t index) {
  function = {module.function(index).canonicalName,
              module.function(index).abiResult,
              source.parameters.size(),
              {},
              {},
              0};
  errorType = module.function(index).error;
  function.genericParameters = module.function(index).genericParameters;
  function.unsafeFunction = source.unsafeFunction;
  function.abi = source.abi;
  function.variadic = source.variadic;
  function.floatingPolicy = module.function(index).floatingPolicy;
  function.variadicCursor = module.function(index).variadicCursor;
  function.targetFeatures = module.function(index).targetFeatures;
  function.foreignDeclaration = source.foreignDeclaration;
  function.externalName = module.function(index).externalName;
  function.exportedDefinition =
      source.body.get() && !function.externalName.empty();
  unsafeDepth = source.unsafeFunction ? 1 : 0;
  function.genericResultSources = module.function(index).genericResultSources;
  function.interfaceBounds = module.function(index).interfaceBounds;
  function.unpinBounds = module.function(index).unpinBounds;
  function.regionSignature = module.function(index).regionSignature;
  function.genericEqualities = module.function(index).genericEqualities;
  function.resultSources = module.function(index).resultSources;
  function.twoPhaseReceiver = source.receiver == "mut";

  for (const auto &local : module.function(index).locals)
    function.locals.push_back({local.name, local.type, local.mutableBinding,
                               local.span, local.mode, 0, 0, local.storage,
                               local.staticIndex});
  if (module.function(index).naked) {
    const Node *assembly = source.body.get();
    if (assembly->kind == Kind::Block)
      assembly = assembly->children[0].get();
    function.nakedAssembly = module.facts(*assembly).assembly;
    return std::move(function);
  }
  if (!source.body.get()) {
    if (source.foreignDeclaration)
      return std::move(function);
    function.declarationOnly = true;
    function.externalName = "<interface-declaration>";
    return std::move(function);
  }
  for (std::size_t p = 0; p < function.locals.size(); ++p) {
    function.locals[p].scope = p < function.parameters ? 0 : -1;
    function.locals[p].order =
        p < function.parameters ? static_cast<std::uint32_t>(p) : 0;
  }
  order = static_cast<std::uint32_t>(function.parameters);
  current = block();
  if (function.variadicCursor >= 0) {
    auto slot = function.variadicCursor;
    function.locals[slot].scope = 0;
    function.locals[slot].order = order++;
    emit({Op::Declare, {}, {}, {}, "", {slot, {}}, -1, 0, source.variadicSpan},
         Type::Unit);
    Instruction start{Op::Machine, {},         {},
                      {},          "va.start", {-1, {}},
                      -1,          0,          source.variadicSpan};
    start.typeArguments = {function.locals[slot].type};
    auto value = emit(std::move(start), function.locals[slot].type);
    emit({Op::Store,
          {},
          {value},
          {},
          "",
          {slot, {}},
          -1,
          0,
          source.variadicSpan},
         Type::Unit);
  }
  for (std::size_t p = 0; p < function.parameters; ++p)
    if (module.typeStore()->uninhabited(function.locals[p].type)) {
      terminate({Exit::Unreachable});
      return std::move(function);
    }
  for (std::size_t i = 0; i < source.parameters.size(); ++i)
    if (source.parameters[i].pattern) {
      Place place{static_cast<int>(i), {}};
      auto type = function.locals[i].type;
      auto mode = function.locals[i].mode;
      while (module.typeStore()->isView(type)) {
        const auto &view = module.typeStore()->view(type);
        mode = mode == ParameterMode::Read ? ParameterMode::Read : view.mode;
        type = view.payload;
        place.fields.push_back(Projection::dereference());
      }
      patternBind(*source.parameters[i].pattern, place, mode);
    }
  constructorSelfSlot = module.function(index).constructorSelfSlot;
  function.constructorSelfSlot = constructorSelfSlot;
  if (constructorSelfSlot >= 0) {
    function.locals[constructorSelfSlot].scope = 0;
    function.locals[constructorSelfSlot].order = order++;
    emit({Op::Declare,
          {},
          {},
          {},
          "",
          {constructorSelfSlot, {}},
          -1,
          0,
          source.span},
         Type::Unit);
    auto selfType = function.locals[constructorSelfSlot].type;
    if (module.typeStore()->product(selfType).fields.empty()) {
      auto empty =
          emit({Op::Construct, {}, {}, {}, "", {-1, {}}, -1, 0, source.span},
               selfType);
      emit({Op::Store,
            {},
            {empty},
            {},
            "",
            {constructorSelfSlot, {}},
            -1,
            0,
            source.span},
           Type::Unit);
    }
  }
  auto result = expression(*source.body);
  if (live()) {
    if (module.facts(*source.body).flow.normal)
      returnValue(result, source.span);
    else
      terminate({Exit::Unreachable});
  }
  for (auto &b : function.blocks)
    if (b.exit.kind == Exit::None)
      b.exit.kind = Exit::Unreachable;
  return std::move(function);
}
int Builder::block() {
  if (function.blocks.size() >= limits::cfgBlocks)
    throw LoweringLimit("CFG block limit exceeded");
  function.blocks.emplace_back();
  return static_cast<int>(function.blocks.size() - 1);
}
bool Builder::live() {
  return function.blocks[current].exit.kind == Exit::None;
}
void Builder::terminate(Terminator exit) {
  function.blocks[current].exit = exit;
}
ir::Value Builder::emit(Instruction instruction, Type type, ir::Access access) {
  instruction.unsafeAllowed |= unsafeDepth != 0;
  instruction.result = {function.values++, type, access};
  auto result = instruction.result;
  function.blocks[current].instructions.push_back(std::move(instruction));
  return result;
}
ir::Value Builder::constant(Type type, std::int32_t number) {
  Instruction instruction{Op::Constant, {}, {},     {}, "",
                          {-1, {}},     -1, number, {}};
  return emit(std::move(instruction), type);
}
ir::Value Builder::constant(Type type, const NumericLiteral &number) {
  Instruction instruction{Op::Constant, {}, {}, {}, "", {-1, {}}, -1, 0, {}};
  instruction.numeric = number;
  return emit(std::move(instruction), type);
}
ir::Value Builder::unit() { return live() ? constant(Type::Unit) : Value{}; }
void Builder::jump(int target) {
  if (live())
    terminate({Exit::Jump, {}, target});
}
void Builder::branch(const Node &condition, Value value, int a, int b) {
  if (!live())
    return;
  if (auto literal = booleanLiteral(condition))
    jump(*literal ? a : b);
  else
    terminate({Exit::Branch, value, a, b});
}
ir::Value Builder::merge(Type type, const std::vector<Value> &values,
                         const std::vector<int> &blocks) {
  if (values.empty()) {
    terminate({Exit::Unreachable});
    return {};
  }
  if (type == Type::Unit)
    return unit();
  Instruction phi{Op::Phi, {}, values, blocks, "", {-1, {}}, -1, 0, {}};
  return emit(std::move(phi), type);
}
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics) {
  ir::Program result;
  result.types = module.typeStore();
  for (std::size_t i = 0; i < module.syntax().functions.size(); ++i)
    if (!module.function(i).library.empty())
      result.libraries.push_back(module.function(i).library);
  for (std::size_t i = 0; i < module.statics().size(); ++i) {
    const auto &facts = module.statics()[i];
    const auto &source = module.syntax().statics[i];
    result.statics.push_back({facts.name, facts.externalName, facts.library,
                              facts.type, source.mutableBinding,
                              source.foreignDeclaration, source.span,
                              facts.initializer});
    if (!facts.library.empty())
      result.libraries.push_back(facts.library);
  }
  result.target = module.target();
  result.globalAssembly = module.globalAssembly();
  try {
    for (std::size_t i = 0; i < module.syntax().functions.size(); ++i)
      result.functions.push_back(
          Builder(module).run(module.syntax().functions[i], i));
    for (std::size_t i = 0; i < module.syntax().functions.size(); ++i)
      for (std::size_t p = 0;
           p < module.syntax().functions[i].parameters.size(); ++p)
        if (module.syntax().functions[i].parameters[p].defaultValue.get())
          result.functions.push_back(
              Builder(module).runDefault(module.syntax().functions[i], i, p));
    for (std::size_t i = 0; i < module.closures().size(); ++i) {
      result.closureFunctions.push_back(
          static_cast<int>(result.functions.size()));
      result.functions.push_back(Builder(module).runClosure(i));
    }
    callableContracts(result);
  } catch (const LoweringLimit &error) {
    diagnostics.error("limit", {}, error.what());
  }
  return result;
}

} // namespace mettle::lowering
