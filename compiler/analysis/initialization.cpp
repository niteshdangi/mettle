#include "analysis/initialization.h"
#include "analysis/place_tree.h"
#include "analysis/value_ownership.h"
#include <deque>
#include <map>
#include <optional>
#include <set>

namespace mettle::analysis {
namespace {
struct State {
  std::vector<bool> definite, possible, ever, moved;
  std::map<Place, std::set<int>> variants{};
  bool operator==(const State &) const = default;
};
void checkFunction(const ir::Function &function, const TypeStore &types,
                   Diagnostics &diagnostics) {
  if (function.blocks.empty())
    return;
  PlaceTree tree(function, types);
  State entry{std::vector<bool>(tree.size()), std::vector<bool>(tree.size()),
              std::vector<bool>(tree.size()), std::vector<bool>(tree.size())};
  std::map<Place, std::set<int>> unknownVariants;
  std::vector<const ir::Instruction *> definitions(function.values, nullptr);
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions) {
      definitions[instruction.result.id] = &instruction;
      if (instruction.place.root < 0)
        continue;
      Place prefix{instruction.place.root, {}};
      auto type = function.locals[prefix.root].type;
      for (std::size_t depth = 0;; ++depth) {
        if (types.isSum(type)) {
          auto &variants = unknownVariants[prefix];
          for (std::size_t i = 0; i < types.product(type).variants.size(); ++i)
            variants.insert(static_cast<int>(i));
        }
        if (depth == instruction.place.fields.size())
          break;
        prefix.fields.push_back(instruction.place.fields[depth]);
        type = *projectedType(types, function.locals[prefix.root].type,
                              prefix.fields);
      }
    }
  entry.variants = unknownVariants;
  auto contains = [](const Place &parent, const Place &child) {
    return parent.root == child.root &&
           parent.fields.size() <= child.fields.size() &&
           std::equal(parent.fields.begin(), parent.fields.end(),
                      child.fields.begin());
  };
  for (std::size_t i = 0; i < function.locals.size(); ++i)
    if (i < function.parameters ||
        function.locals[i].storage == StorageDuration::Static)
      for (auto *bits : {&entry.definite, &entry.possible, &entry.ever})
        tree.set(*bits, tree.index({static_cast<int>(i), {}}), true);
  auto apply = [&](State &state, const ir::Instruction &instruction) {
    auto forget = [&](const Place &place) {
      for (const auto &[sum, unknown] : unknownVariants)
        if (contains(place, sum))
          state.variants[sum] = unknown;
    };
    if (instruction.op == ir::Op::Call ||
        instruction.op == ir::Op::IndirectCall ||
        instruction.op == ir::Op::CatchCall) {
      for (auto operand : instruction.operands)
        if (operand.access == ir::Access::Mut ||
            (types.isView(operand.type) &&
             types.view(operand.type).mode == ParameterMode::Mut)) {
          const auto *definition = definitions[operand.id];
          if (definition && definition->place.root >= 0)
            forget(definition->place);
          else
            state.variants = unknownVariants;
        }
    }
    if (instruction.op == ir::Op::Store ||
        instruction.op == ir::Op::StorageWrite) {
      forget(instruction.place);
      const auto *value = definitions[instruction.operands[0].id];
      if (value && value->op == ir::Op::VariantConstruct &&
          state.variants.contains(instruction.place))
        state.variants[instruction.place] = {value->number};
    }
    if (instruction.op == ir::Op::ScopeExit) {
      for (std::size_t l = 0; l < function.locals.size(); ++l) {
        const auto &local = function.locals[l];
        if (local.storage == StorageDuration::Static ||
            local.scope != instruction.number ||
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
        instruction.op != ir::Op::StorageWrite &&
        instruction.op != ir::Op::Move && instruction.op != ir::Op::DropPlace)
      return;
    auto index = tree.index(instruction.place);
    if (instruction.op == ir::Op::Declare) {
      for (auto *bits :
           {&state.definite, &state.possible, &state.ever, &state.moved})
        tree.set(*bits, index, false);
    } else {
      bool initialized = instruction.op == ir::Op::Store ||
                         instruction.op == ir::Op::StorageWrite;
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
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      successors.push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      successors.push_back(exit.second);
    for (auto next : successors) {
      auto incoming = out;
      if (exit.kind == ir::Exit::Branch) {
        const auto *condition = definitions[exit.value.id];
        if (condition && condition->op == ir::Op::VariantTest) {
          auto &variants = incoming.variants[condition->place];
          if (next == exit.first) {
            bool possible = variants.contains(condition->number);
            variants.clear();
            if (possible)
              variants.insert(condition->number);
          } else
            variants.erase(condition->number);
        }
      }
      auto merged = inputs[next].value_or(incoming);
      for (std::size_t i = 0; i < tree.size(); ++i) {
        merged.definite[i] = merged.definite[i] && incoming.definite[i];
        merged.possible[i] = merged.possible[i] || incoming.possible[i];
        merged.ever[i] = merged.ever[i] || incoming.ever[i];
        merged.moved[i] = merged.moved[i] || incoming.moved[i];
      }
      for (const auto &[place, variants] : incoming.variants)
        merged.variants[place].insert(variants.begin(), variants.end());
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
        if (local.storage == StorageDuration::Static && local.mutableBinding &&
            !instruction.unsafeAllowed)
          diagnostics.error("unsafe", instruction.span,
                            "mutable-static access requires unsafe");
        auto type = local.type;
        Place prefix{instruction.place.root, {}};
        for (auto projection : instruction.place.fields) {
          if (types.isSum(type) && projection.kind == Projection::Kind::Field &&
              projection.index == 0 && instruction.op == ir::Op::Store)
            diagnostics.error("internal", instruction.span,
                              "sum tags require variant construction");
          if (types.isSum(type) && projection.kind == Projection::Kind::Field &&
              projection.index != 0) {
            const auto &sum = types.product(type);
            const auto &variants = state.variants[prefix];
            for (auto variant : variants)
              if (std::find(sum.variants[variant].fields.begin(),
                            sum.variants[variant].fields.end(),
                            projection.index) ==
                  sum.variants[variant].fields.end())
                diagnostics.error(
                    "internal", instruction.span,
                    "variant payload accessed without a valid tag refinement");
          }
          if (projection.kind == Projection::Kind::Dereference) {
            if (!tree.all(state.definite, tree.index(prefix)))
              diagnostics.error("type", instruction.span,
                                "view handle may be uninitialized");
            reference = true;
            readOnly = (types.isPointer(type) ? false : readOnly) ||
                       types.view(type).mode == ParameterMode::Read;
            writable = !readOnly && types.view(type).mode == ParameterMode::Mut;
            type = types.view(type).payload;
          } else if (projection.kind == Projection::Kind::Slice)
            type = projection.type;
          else
            type = types.product(type).fields[projection.index].type;
          prefix.fields.push_back(projection);
        }
      }
      if (instruction.op == ir::Op::Load || instruction.op == ir::Op::Move ||
          instruction.op == ir::Op::DropPlace ||
          instruction.op == ir::Op::VariantTest ||
          instruction.op == ir::Op::BorrowRead ||
          instruction.op == ir::Op::BorrowMut ||
          instruction.op == ir::Op::ReserveMut ||
          instruction.op == ir::Op::ViewRead ||
          instruction.op == ir::Op::ArrayBorrowRead ||
          instruction.op == ir::Op::ArrayBorrowMut ||
          instruction.op == ir::Op::ArrayTake ||
          instruction.op == ir::Op::EraseView ||
          instruction.op == ir::Op::ErasedUpcast ||
          instruction.op == ir::Op::UnsizeView ||
          instruction.op == ir::Op::SliceLength ||
          instruction.op == ir::Op::SliceBorrowRead ||
          instruction.op == ir::Op::SliceBorrowMut ||
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
        if (function.locals[instruction.place.root].storage ==
            StorageDuration::Static)
          diagnostics.error("ownership", instruction.span,
                            "cannot move out of static storage");
        if (reference) {
          auto moved =
              projectedType(types, function.locals[instruction.place.root].type,
                            instruction.place.fields);
          // `take` consumes a Copy value too; an explicit copy is the fix.
          diagnostics.error(
              "ownership", instruction.span,
              moved && types.isCopy(*moved)
                  ? "cannot move out of a borrowed place; a `take` argument "
                    "consumes its value, so copy it into a binding first"
                  : "cannot move out of a borrowed place");
        }
        Place prefix{instruction.place.root, {}};
        auto type = function.locals[prefix.root].type;
        for (auto projection : instruction.place.fields) {
          if (!reference && types.isProduct(type) &&
              (types.product(type).hasDestructor ||
               types.product(type).nativeCleanup != NativeCleanup::None) &&
              tree.all(state.possible, tree.index(prefix)))
            diagnostics.error(
                "ownership", instruction.span,
                "cannot partially move a value with a user destructor");
          prefix.fields.push_back(projection);
          type = *projectedType(types, function.locals[prefix.root].type,
                                prefix.fields);
        }
        if ((instruction.op == ir::Op::DropPlace ||
             instruction.op == ir::Op::ArrayTake) &&
            function.locals[instruction.place.root].storage ==
                StorageDuration::Static)
          diagnostics.error("ownership", instruction.span,
                            "cannot consume static storage");
      }
      if (instruction.op == ir::Op::Declare &&
          types.needsDrop(function.locals[instruction.place.root].type) &&
          tree.any(state.possible, tree.index(instruction.place)))
        diagnostics.error("internal", instruction.span,
                          "declaration discards live owned storage");
      if (instruction.op == ir::Op::StorageWrite) {
        auto owner = instruction.place;
        owner.fields.pop_back();
        if (!tree.all(state.definite, tree.index(owner)))
          diagnostics.error("type", instruction.span,
                            "storage handle may be uninitialized");
      }
      if ((instruction.op == ir::Op::Store ||
           instruction.op == ir::Op::StorageWrite) &&
          readOnly)
        diagnostics.error("ownership", instruction.span,
                          "cannot write through a read parameter");
      if (instruction.op == ir::Op::BorrowMut ||
          instruction.op == ir::Op::DropPlace ||
          instruction.op == ir::Op::ArrayTake ||
          instruction.op == ir::Op::ArrayBorrowMut ||
          instruction.op == ir::Op::ReserveMut ||
          (instruction.op == ir::Op::EraseView &&
           types.view(instruction.result.type).mode == ParameterMode::Mut) ||
          (instruction.op == ir::Op::UnsizeView &&
           types.view(instruction.result.type).mode == ParameterMode::Mut) ||
          (instruction.op == ir::Op::ErasedUpcast &&
           types.view(instruction.result.type).mode == ParameterMode::Mut) ||
          instruction.op == ir::Op::SliceBorrowMut ||
          instruction.op == ir::Op::ViewMut) {
        if (readOnly || !writable)
          diagnostics.error("ownership", instruction.span,
                            "exclusive borrow requires a mutable place");
      }
      if ((instruction.op == ir::Op::Store ||
           instruction.op == ir::Op::StorageWrite) &&
          !readOnly && !writable &&
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
        if (!borrowed && storage.storage != StorageDuration::Static &&
            types.needsDrop(storage.type) &&
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
