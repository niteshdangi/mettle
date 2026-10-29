#include "ir/target.h"
#include "ir/dominance.h"
#include <algorithm>
#include <iterator>

namespace mettle::ir {
bool verifyTarget(const Program &program, Diagnostics &diagnostics) {
  bool valid = true;
  auto fail = [&](Span span, std::string message) {
    diagnostics.error("feature", span, std::move(message));
    valid = false;
  };
  auto selected = targetFacts(program.target.triple);
  if (selected.arch != program.target.arch ||
      selected.system != program.target.system ||
      selected.pointerBits != program.target.pointerBits ||
      selected.littleEndian != program.target.littleEndian ||
      selected.baseline != program.target.baseline)
    fail({}, "compiler-owned target facts do not match the selected profile");
  auto assembly = [&](const Assembly &code,
                      const std::set<std::string> &features, Span span) {
    if (auto failure =
            validateAssembly(*program.types, program.target, features, code))
      fail(span, *failure);
    for (const auto &operand : code.operands)
      if (operand.mode == AssemblyMode::Sym &&
          (operand.symbol < 0 ||
           static_cast<std::size_t>(operand.symbol) >=
               (operand.symbolKind == AssemblyOperand::SymbolKind::Function
                    ? program.functions.size()
                    : program.statics.size())))
        fail(span, "assembly references an unresolved symbol identity");
  };
  for (const auto &code : program.globalAssembly)
    assembly(code, {}, {});
  for (const auto &function : program.functions) {
    auto baseline = function.targetFeatures;
    baseline.insert(program.target.baseline.begin(),
                    program.target.baseline.end());
    baseline = featureClosure(program.target.arch, std::move(baseline));
    for (const auto &feature : function.targetFeatures)
      if (!program.target.initialProfile() ||
          !recognizedFeature(program.target.arch, feature))
        fail({}, "unknown or unavailable function target feature");
    if (function.nakedAssembly) {
      if (function.abi.empty() || !function.unsafeFunction ||
          !function.blocks.empty() || function.variadic ||
          function.variadicCursor >= 0 ||
          function.parameters != function.locals.size() ||
          function.nakedAssembly->variant != AssemblyVariant::Naked)
        fail({}, "invalid naked physical entry contract");
      if (program.types->needsDrop(function.result))
        fail({}, "naked physical entry has a managed result");
      for (std::size_t p = 0; p < function.parameters; ++p) {
        const auto &parameter = function.locals[p];
        if ((parameter.mode == ParameterMode::Value ||
             parameter.mode == ParameterMode::Take) &&
            program.types->needsDrop(parameter.type))
          fail({}, "naked physical entry has an owned cleanup root");
      }
      assembly(*function.nakedAssembly, baseline, {});
    }
    if (function.blocks.empty())
      continue;
    Dominance dominance(function);
    std::vector<const Instruction *> definitions(function.values, nullptr);
    std::set<std::string> universe = baseline;
    for (const auto &block : function.blocks)
      for (const auto &instruction : block.instructions) {
        definitions[instruction.result.id] = &instruction;
        if (instruction.op == Op::FeatureTest) {
          if (!program.target.initialProfile() ||
              !recognizedFeature(program.target.arch, instruction.text) ||
              (program.target.arch == TargetArch::Aarch64 &&
               !program.target.baseline.contains(instruction.text)))
            fail(instruction.span, "unsupported runtime feature detector");
          universe.insert(instruction.text);
        }
      }
    universe = featureClosure(program.target.arch, std::move(universe));
    std::vector<std::set<std::string>> available(function.blocks.size(),
                                                 universe);
    available[0] = baseline;
    bool changed;
    do {
      changed = false;
      for (std::size_t block = 1; block < function.blocks.size(); ++block) {
        if (!dominance.reachable(block))
          continue;
        auto incoming = universe;
        for (auto predecessor : dominance.predecessors[block]) {
          if (!dominance.reachable(predecessor))
            continue;
          auto edge = available[predecessor];
          const auto &exit = function.blocks[predecessor].exit;
          if (exit.kind == Exit::Branch &&
              exit.first == static_cast<int>(block) &&
              exit.first != exit.second) {
            const auto *condition = definitions[exit.value.id];
            if (condition && condition->op == Op::FeatureTest)
              edge.insert(condition->text);
          }
          edge = featureClosure(program.target.arch, std::move(edge));
          std::set<std::string> intersection;
          std::set_intersection(
              incoming.begin(), incoming.end(), edge.begin(), edge.end(),
              std::inserter(intersection, intersection.end()));
          incoming = std::move(intersection);
        }
        if (available[block] != incoming) {
          available[block] = std::move(incoming);
          changed = true;
        }
      }
    } while (changed);
    for (std::size_t block = 0; block < function.blocks.size(); ++block) {
      for (const auto &instruction : function.blocks[block].instructions) {
        std::set<std::string> required;
        if (auto operation = targetOperation(instruction.text);
            instruction.op == Op::Machine && operation) {
          if (targetVector(operation->vector)->arch != program.target.arch)
            fail(instruction.span, "architecture operation target mismatch");
          required.insert(operation->feature);
        }
        if (instruction.op == Op::Machine && instruction.text == "va.arg")
          if (auto vector =
                  targetVector(program.types->name(instruction.result.type))) {
            if (vector->arch != program.target.arch)
              fail(instruction.span, "variadic vector target mismatch");
            required.insert(vector->feature);
          }
        if (instruction.op == Op::Call || instruction.op == Op::CatchCall)
          required = program.functions[instruction.callee].targetFeatures;
        if (instruction.op == Op::IndirectCall)
          required =
              program.types->callable(instruction.indirectType).targetFeatures;
        if (!required.empty() &&
            !featuresAvailable(program.target,
                               dominance.reachable(block) ? available[block]
                                                          : baseline,
                               required))
          fail(instruction.span, "target operation/call lacks a dominating "
                                 "feature contract or dispatch guard");
        if (instruction.assembly)
          assembly(*instruction.assembly,
                   dominance.reachable(block) ? available[block] : baseline,
                   instruction.span);
      }
    }
  }
  return valid;
}
} // namespace mettle::ir
