#include "analysis/liveness.h"
#include <deque>
#include <map>
#include <utility>

namespace mettle::analysis {
ValueLiveness valueLiveness(const ir::Function &function) {
  const auto count = function.blocks.size();
  ValueLiveness result;
  result.in.resize(count);
  result.out.resize(count);
  std::vector<std::set<int>> uses(count), definitions(count);
  std::vector<std::vector<int>> successors(count), predecessors(count);
  std::vector<std::map<int, std::set<int>>> phiInputs(count);
  auto use = [&](std::size_t block, ir::Value value) {
    if (!definitions[block].contains(value.id))
      uses[block].insert(value.id);
  };
  for (std::size_t b = 0; b < count; ++b) {
    const auto &block = function.blocks[b];
    for (const auto &instruction : block.instructions) {
      if (instruction.op == ir::Op::Phi) {
        for (std::size_t i = 0; i < instruction.operands.size(); ++i)
          phiInputs[b][instruction.predecessors[i]].insert(
              instruction.operands[i].id);
      } else {
        for (auto operand : instruction.operands)
          use(b, operand);
        if (instruction.op == ir::Op::IndirectCall)
          use(b, instruction.target);
      }
      definitions[b].insert(instruction.result.id);
    }
    if (block.exit.kind == ir::Exit::Branch ||
        block.exit.kind == ir::Exit::Return)
      use(b, block.exit.value);
    if (block.exit.kind == ir::Exit::Jump ||
        block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.first);
    if (block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.second);
    for (auto successor : successors[b])
      predecessors[successor].push_back(static_cast<int>(b));
  }
  std::deque<int> work;
  std::vector<bool> queued(count, true);
  for (std::size_t b = 0; b < count; ++b)
    work.push_back(static_cast<int>(b));
  while (!work.empty()) {
    auto b = work.front();
    work.pop_front();
    queued[b] = false;
    std::set<int> out;
    for (auto successor : successors[b]) {
      out.insert(result.in[successor].begin(), result.in[successor].end());
      if (auto inputs = phiInputs[successor].find(b);
          inputs != phiInputs[successor].end())
        out.insert(inputs->second.begin(), inputs->second.end());
    }
    auto in = uses[b];
    for (auto value : out)
      if (!definitions[b].contains(value))
        in.insert(value);
    result.out[b] = std::move(out);
    if (result.in[b] == in)
      continue;
    result.in[b] = std::move(in);
    for (auto predecessor : predecessors[b])
      if (!queued[predecessor]) {
        queued[predecessor] = true;
        work.push_back(predecessor);
      }
  }
  return result;
}
} // namespace mettle::analysis
