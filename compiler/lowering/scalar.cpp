#include "lowering/builder.h"

namespace mettle::lowering {
using ir::Exit;
using ir::Op;
ir::Function Builder::run(const mettle::Function &source, std::size_t index) {
  function = {source.name,
              module.function(index).result,
              source.parameters.size(),
              {},
              {},
              0};

  for (const auto &local : module.function(index).locals)
    function.locals.push_back(
        {local.name, local.type, local.mutableBinding, local.span, local.mode});
  function.resultSources = module.function(index).resultSources;
  function.twoPhaseReceiver = source.receiver == "mut";
  for (std::size_t p = 0; p < function.locals.size(); ++p) {
    function.locals[p].scope = p < function.parameters ? 0 : -1;
    function.locals[p].order =
        p < function.parameters ? static_cast<std::uint32_t>(p) : 0;
  }
  order = static_cast<std::uint32_t>(function.parameters);
  current = block();
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
  try {
    for (std::size_t i = 0; i < module.syntax().functions.size(); ++i)
      result.functions.push_back(
          Builder(module).run(module.syntax().functions[i], i));
  } catch (const LoweringLimit &error) {
    diagnostics.error("limit", {}, error.what());
  }
  return result;
}

} // namespace mettle::lowering
