#include "analysis/value_ownership.h"
#include <algorithm>
#include <deque>
#include <map>
#include <optional>
#include <set>

namespace mettle::analysis {
namespace {
constexpr unsigned char live = 1, consumed = 2;
using State = std::map<int, unsigned char>;
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
  const auto count = function.blocks.size();
  std::vector<std::vector<int>> successors(count), predecessors(count);
  std::vector<std::set<int>> needed(count), defined(count), liveIn(count);
  for (std::size_t b = 0; b < count; ++b) {
    const auto &block = function.blocks[b];
    auto read = [&](ir::Value value) {
      auto index = indices[value.id];
      if (index >= 0 && !defined[b].contains(index))
        needed[b].insert(index);
    };
    for (const auto &instruction : block.instructions) {
      if (instruction.op == ir::Op::IndirectCall)
        read(instruction.target);
      if (instruction.op != ir::Op::Phi)
        for (auto operand : instruction.operands)
          read(operand);
      if (auto index = indices[instruction.result.id]; index >= 0)
        defined[b].insert(index);
    }
    if (block.exit.kind == ir::Exit::Return)
      read(block.exit.value);
    if (ir::continues(block.exit.kind) || block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.first);
    if (block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.second);
    for (auto next : successors[b]) {
      predecessors[next].push_back(static_cast<int>(b));
      for (const auto &instruction : function.blocks[next].instructions) {
        if (instruction.op != ir::Op::Phi)
          break;
        auto found =
            std::find(instruction.predecessors.begin(),
                      instruction.predecessors.end(), static_cast<int>(b));
        auto operand =
            static_cast<std::size_t>(found - instruction.predecessors.begin());
        read(instruction.operands[operand]);
      }
    }
  }
  std::deque<int> work;
  std::vector<bool> queued(count, true);
  for (std::size_t b = count; b-- > 0;)
    work.push_back(static_cast<int>(b));
  while (!work.empty()) {
    auto b = work.front();
    work.pop_front();
    queued[b] = false;
    auto incoming = needed[b];
    for (auto next : successors[b])
      for (auto index : liveIn[next])
        if (!defined[b].contains(index))
          incoming.insert(index);
    if (incoming == liveIn[b])
      continue;
    liveIn[b] = std::move(incoming);
    for (auto previous : predecessors[b])
      if (!queued[previous]) {
        queued[previous] = true;
        work.push_back(previous);
      }
  }
  needed.clear();
  defined.clear();
  std::vector<bool> needsDrop;
  needsDrop.reserve(owned.size());
  for (auto type : owned)
    needsDrop.push_back(types.needsDrop(type));
  auto use = [&](State &state, ir::Value value, bool transfer, Span span,
                 bool report) {
    int index = indices[value.id];
    if (index < 0)
      return;
    auto found = state.find(index);
    if (report && found != state.end() && (found->second & consumed))
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
        for (auto [index, bits] : state)
          if ((bits & live) && needsDrop[index])
            diagnostics.error(
                "internal", {},
                "owned SSA value reaches return without transfer or cleanup");
    }
    return state;
  };
  using Input = std::vector<std::pair<int, unsigned char>>;
  std::vector<std::optional<Input>> inputs(count);
  inputs[0] = Input{};
  queued.assign(count, false);
  queued[0] = true;
  work.push_back(0);
  while (!work.empty()) {
    int block = work.front();
    work.pop_front();
    queued[block] = false;
    auto state = apply(State(inputs[block]->begin(), inputs[block]->end()),
                       block, false);
    for (int successor : successors[block]) {
      auto incoming = edge(state, block, successor, false);
      std::erase_if(incoming, [&](const auto &item) {
        return !liveIn[successor].contains(item.first) &&
               (!(item.second & live) || !needsDrop[item.first]);
      });
      const Input empty;
      const auto &previous = inputs[successor] ? *inputs[successor] : empty;
      Input merged;
      merged.reserve(std::max(previous.size(), incoming.size()));
      auto old = previous.begin();
      for (auto [index, bits] : incoming) {
        while (old != previous.end() && old->first < index)
          merged.push_back(*old++);
        if (old != previous.end() && old->first == index)
          bits |= (old++)->second;
        merged.emplace_back(index, bits);
      }
      merged.insert(merged.end(), old, previous.end());
      if (!inputs[successor] || *inputs[successor] != merged) {
        inputs[successor] = std::move(merged);
        if (!queued[successor]) {
          queued[successor] = true;
          work.push_back(successor);
        }
      }
    }
  }
  for (std::size_t block = 0; block < function.blocks.size(); ++block) {
    if (!inputs[block])
      continue;
    auto state = apply(State(inputs[block]->begin(), inputs[block]->end()),
                       static_cast<int>(block), true);
    const auto &exit = function.blocks[block].exit;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      edge(state, static_cast<int>(block), exit.first, true);
    if (exit.kind == ir::Exit::Branch)
      edge(state, static_cast<int>(block), exit.second, true);
  }
}
} // namespace mettle::analysis
