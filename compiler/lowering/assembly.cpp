#include "lowering/builder.h"

namespace mettle::lowering {
Builder::Value Builder::assemblyExpression(const Node &node) {
  const auto &facts = module.facts(node);
  const auto &assembly = *facts.assembly;
  std::vector<Value> inputs;
  std::vector<Place> outputs;
  // Place lowering materializes dynamic base/index expressions. Retaining those
  // places, rather than lowering the syntax again after asm, preserves
  // once-only source-order evaluation and normal-completion-only output
  // publication.
  for (std::size_t i = 0; i < assembly.operands.size(); ++i) {
    const auto &operand = assembly.operands[i];
    const auto &syntax = node.assembly->operands[i];
    if (operand.mode == AssemblyMode::Const ||
        operand.mode == AssemblyMode::Sym)
      continue;
    if (assemblyInput(operand.mode)) {
      if (syntax.input == syntax.output) {
        auto destination = place(*node.children[syntax.input], false, true);
        if (!live())
          return {};
        inputs.push_back(
            emit({ir::Op::Load, {}, {}, {}, "", destination, -1, 0, node.span},
                 operand.inputType));
        outputs.push_back(std::move(destination));
        continue;
      }
      inputs.push_back(use(expression(*node.children[syntax.input])));
      if (!live())
        return {};
    }
    if (assemblyOutput(operand.mode) && !operand.discard) {
      outputs.push_back(place(*node.children[syntax.output], false, true));
      if (!live())
        return {};
    }
  }
  Instruction instruction{
      ir::Op::Assembly, {}, std::move(inputs), {}, "", {-1, {}}, -1, 0,
      node.span};
  instruction.assembly = assembly;
  auto result = emit(std::move(instruction), facts.machineType);
  if (assembly.options.contains("noreturn")) {
    terminate({ir::Exit::Unreachable});
    return {};
  }
  for (std::size_t i = 0; i < outputs.size(); ++i) {
    auto type = module.typeStore()->product(facts.machineType).fields[i].type;
    auto output = emit({ir::Op::Project,
                        {},
                        {result},
                        {},
                        "",
                        {-1, {}},
                        -1,
                        static_cast<std::int32_t>(i),
                        node.span},
                       type);
    emit({ir::Op::Store, {}, {output}, {}, "", outputs[i], -1, 0, node.span},
         Type::Unit);
  }
  return unit();
}
} // namespace mettle::lowering
