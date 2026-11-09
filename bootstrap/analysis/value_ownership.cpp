#include "analysis/value_ownership.h"
#include <algorithm>
#include <deque>
#include <optional>

namespace mettle::analysis {
namespace {
constexpr unsigned char live = 1, consumed = 2;
using State = std::vector<unsigned char>;
} // namespace

void valueOwnership(const ir::Function &function, const TypeStore &types,
                    Diagnostics &diagnostics) {
  if (function.blocks.empty())
    return;
  std::vector<int> indices(function.values, -1);
  std::vector<Type> owned;
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions)
      if (instruction.result.access == ir::Access::Owned &&
          instruction.result.type != Type::Never &&
          !types.isCopy(instruction.result.type)) {
        indices[instruction.result.id] = static_cast<int>(owned.size());
        owned.push_back(instruction.result.type);
      }
  if (owned.empty())
    return;
  auto use = [&](State &state, ir::Value value, bool transfer, Span span,
                 bool report) {
    int index = indices[value.id];
    if (index < 0)
      return;
    if (report && (state[index] & consumed))
      diagnostics.error("internal", span,
                        "non-Copy SSA value may already have been consumed");
    if (transfer)
      state[index] = consumed;
  };
  auto edge = [&](State state, int predecessor, int successor, bool report) {
    for (const auto &instruction : function.blocks[successor].instructions) {
      if (instruction.op != ir::Op::Phi)
        break;
      auto found = std::find(instruction.predecessors.begin(),
                             instruction.predecessors.end(), predecessor);
      auto index =
          static_cast<std::size_t>(found - instruction.predecessors.begin());
      use(state, instruction.operands[index], true, instruction.span, report);
    }
    return state;
  };
  auto apply = [&](State state, int block, bool report) {
    const auto &body = function.blocks[block];
    for (const auto &instruction : body.instructions) {
      if (instruction.op == ir::Op::IndirectCall)
        use(state, instruction.target, true, instruction.span, report);
      if (instruction.op != ir::Op::Phi)
        for (auto operand : instruction.operands)
          // Witness lookup reads metadata; the receiver is transferred by
          // the dispatched call.
          use(state, operand,
              instruction.op != ir::Op::Project &&
                  instruction.op != ir::Op::WitnessMethod,
              instruction.span, report);
      int index = indices[instruction.result.id];
      if (index >= 0)
        state[index] = live;
    }
    if (body.exit.kind == ir::Exit::Return) {
      use(state, body.exit.value, true, {}, report);
      if (report)
        for (std::size_t index = 0; index < owned.size(); ++index)
          if ((state[index] & live) && types.needsDrop(owned[index]))
            diagnostics.error(
                "internal", {},
                "owned SSA value reaches return without transfer or cleanup");
    }
    return state;
  };
  std::vector<std::optional<State>> inputs(function.blocks.size()),
      outputs(function.blocks.size());
  inputs[0] = State(owned.size());
  std::deque<int> work{0};
  while (!work.empty()) {
    int block = work.front();
    work.pop_front();
    auto state = apply(*inputs[block], block, false);
    if (outputs[block] && *outputs[block] == state)
      continue;
    outputs[block] = state;
    const auto &exit = function.blocks[block].exit;
    std::vector<int> successors;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      successors.push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      successors.push_back(exit.second);
    for (int successor : successors) {
      auto incoming = edge(state, block, successor, false);
      auto merged = inputs[successor].value_or(incoming);
      for (std::size_t index = 0; index < owned.size(); ++index)
        merged[index] |= incoming[index];
      if (!inputs[successor] || *inputs[successor] != merged) {
        inputs[successor] = std::move(merged);
        work.push_back(successor);
      }
    }
  }
  for (std::size_t block = 0; block < function.blocks.size(); ++block) {
    if (!inputs[block])
      continue;
    apply(*inputs[block], static_cast<int>(block), true);
    const auto &exit = function.blocks[block].exit;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      edge(*outputs[block], static_cast<int>(block), exit.first, true);
    if (exit.kind == ir::Exit::Branch)
      edge(*outputs[block], static_cast<int>(block), exit.second, true);
  }
}
} // namespace mettle::analysis
