#include "analysis/initialization.h"
#include "analysis/place_tree.h"
#include "analysis/value_ownership.h"
#include <deque>
#include <optional>

namespace mettle::analysis {
namespace {
struct State {
  std::vector<bool> definite, possible, ever, moved;
  bool operator==(const State &) const = default;
};
void checkFunction(const ir::Function &function, const TypeStore &types,
                   Diagnostics &diagnostics) {
  if (function.blocks.empty())
    return;
  PlaceTree tree(function, types);
  State entry{std::vector<bool>(tree.size()), std::vector<bool>(tree.size()),
              std::vector<bool>(tree.size()), std::vector<bool>(tree.size())};
  for (std::size_t i = 0; i < function.parameters; ++i)
    for (auto *bits : {&entry.definite, &entry.possible, &entry.ever})
      tree.set(*bits, tree.index({static_cast<int>(i), {}}), true);
  auto apply = [&](State &state, const ir::Instruction &instruction) {
    if (instruction.op == ir::Op::ScopeExit) {
      for (std::size_t l = 0; l < function.locals.size(); ++l) {
        const auto &local = function.locals[l];
        if (local.scope != instruction.number ||
            (l < function.parameters && (local.mode == ParameterMode::Read ||
                                         local.mode == ParameterMode::Mut)))
          continue;
        auto index = tree.index({static_cast<int>(l), {}});
        for (auto *bits : {&state.definite, &state.possible, &state.moved})
          tree.set(*bits, index, false);
      }
      return;
    }
    if (instruction.op != ir::Op::Declare && instruction.op != ir::Op::Store &&
        instruction.op != ir::Op::Move)
      return;
    auto index = tree.index(instruction.place);
    if (instruction.op == ir::Op::Declare) {
      for (auto *bits :
           {&state.definite, &state.possible, &state.ever, &state.moved})
        tree.set(*bits, index, false);
    } else {
      bool initialized = instruction.op == ir::Op::Store;
      tree.set(state.definite, index, initialized);
      tree.set(state.possible, index, initialized);
      tree.set(state.moved, index, !initialized);
      if (initialized)
        tree.set(state.ever, index, true);
    }
  };
  std::vector<std::optional<State>> inputs(function.blocks.size()),
      outputs(function.blocks.size());
  inputs[0] = entry;
  std::deque<int> work{0};
  while (!work.empty()) {
    int block = work.front();
    work.pop_front();
    auto out = *inputs[block];
    for (const auto &instruction : function.blocks[block].instructions)
      apply(out, instruction);
    if (outputs[block] && *outputs[block] == out)
      continue;
    outputs[block] = out;
    const auto &exit = function.blocks[block].exit;
    std::vector<int> successors;
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch)
      successors.push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      successors.push_back(exit.second);
    for (auto next : successors) {
      auto merged = inputs[next].value_or(out);
      for (std::size_t i = 0; i < tree.size(); ++i) {
        merged.definite[i] = merged.definite[i] && out.definite[i];
        merged.possible[i] = merged.possible[i] || out.possible[i];
        merged.ever[i] = merged.ever[i] || out.ever[i];
        merged.moved[i] = merged.moved[i] || out.moved[i];
      }
      if (!inputs[next] || *inputs[next] != merged) {
        inputs[next] = std::move(merged);
        work.push_back(next);
      }
    }
  }
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    if (!inputs[b])
      continue;
    auto state = *inputs[b];
    for (const auto &instruction : function.blocks[b].instructions) {
      bool reference = false, writable = false, readOnly = false;
      if (instruction.place.root >= 0) {
        const auto &local = function.locals[instruction.place.root];
        reference = local.mode == ParameterMode::Read ||
                    local.mode == ParameterMode::Mut;
        readOnly = local.mode == ParameterMode::Read;
        writable = local.mutableBinding || local.mode == ParameterMode::Mut;
        auto type = local.type;
        Place prefix{instruction.place.root, {}};
        for (auto projection : instruction.place.fields) {
          if (projection.kind == Projection::Kind::Dereference) {
            if (!tree.all(state.definite, tree.index(prefix)))
              diagnostics.error("type", instruction.span,
                                "view handle may be uninitialized");
            reference = true;
            readOnly |= types.view(type).mode == ParameterMode::Read;
            writable = !readOnly && types.view(type).mode == ParameterMode::Mut;
            type = types.view(type).payload;
          } else
            type = types.product(type).fields[projection.index].type;
          prefix.fields.push_back(projection);
        }
      }
      if (instruction.op == ir::Op::Load || instruction.op == ir::Op::Move ||
          instruction.op == ir::Op::BorrowRead ||
          instruction.op == ir::Op::BorrowMut ||
          instruction.op == ir::Op::ReserveMut ||
          instruction.op == ir::Op::ViewRead ||
          instruction.op == ir::Op::ViewMut) {
        auto index = tree.index(instruction.place);
        if (!tree.all(state.definite, index)) {
          bool moved = tree.any(state.moved, index);
          diagnostics.error(
              moved ? "ownership" : "type", instruction.span,
              "binding '" + tree.name(index) +
                  (moved ? "' may have been moved" : "' may be uninitialized"));
        }
      }
      if (instruction.op == ir::Op::Move) {
        if (reference)
          diagnostics.error("ownership", instruction.span,
                            "cannot move out of a borrowed place");
        Place prefix{instruction.place.root, {}};
        auto type = function.locals[prefix.root].type;
        for (auto projection : instruction.place.fields) {
          if (types.isProduct(type) && types.product(type).hasDestructor &&
              tree.all(state.possible, tree.index(prefix)))
            diagnostics.error(
                "ownership", instruction.span,
                "cannot partially move a value with a user destructor");
          prefix.fields.push_back(projection);
          type = *projectedType(types, function.locals[prefix.root].type,
                                prefix.fields);
        }
      }
      if (instruction.op == ir::Op::Declare &&
          types.needsDrop(function.locals[instruction.place.root].type) &&
          tree.any(state.possible, tree.index(instruction.place)))
        diagnostics.error("internal", instruction.span,
                          "declaration discards live owned storage");
      if (instruction.op == ir::Op::Store && readOnly)
        diagnostics.error("ownership", instruction.span,
                          "cannot write through a read parameter");
      if (instruction.op == ir::Op::BorrowMut ||
          instruction.op == ir::Op::ReserveMut ||
          instruction.op == ir::Op::ViewMut) {
        if (readOnly || !writable)
          diagnostics.error("ownership", instruction.span,
                            "exclusive borrow requires a mutable place");
      }
      if (instruction.op == ir::Op::Store && !writable &&
          tree.any(state.ever, tree.index(instruction.place)))
        diagnostics.error("type", instruction.span,
                          "cannot assign immutable binding '" +
                              tree.name(tree.index(instruction.place)) +
                              "' more than once");
      apply(state, instruction);
    }
    if (function.blocks[b].exit.kind == ir::Exit::Return)
      for (std::size_t local = 0; local < function.locals.size(); ++local) {
        const auto &storage = function.locals[local];
        bool borrowed = local < function.parameters &&
                        (storage.mode == ParameterMode::Read ||
                         storage.mode == ParameterMode::Mut);
        if (!borrowed && types.needsDrop(storage.type) &&
            tree.any(state.possible, tree.index({static_cast<int>(local), {}})))
          diagnostics.error(
              "internal", storage.span,
              "owned storage reaches return without scope cleanup");
      }
  }
}
} // namespace
void initialization(const ir::Program &program, Diagnostics &diagnostics) {
  for (const auto &function : program.functions) {
    valueOwnership(function, *program.types, diagnostics);
    checkFunction(function, *program.types, diagnostics);
  }
}
} // namespace mettle::analysis
