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
};
bool readsPlace(ir::Op op) {
  return op == ir::Op::Load || op == ir::Op::Move || op == ir::Op::DropPlace ||
         op == ir::Op::VariantTest || op == ir::Op::BorrowRead ||
         op == ir::Op::BorrowMut || op == ir::Op::ReserveMut ||
         op == ir::Op::ViewRead || op == ir::Op::ArrayBorrowRead ||
         op == ir::Op::ArrayBorrowMut || op == ir::Op::ArrayTake ||
         op == ir::Op::EraseView || op == ir::Op::ErasedUpcast ||
         op == ir::Op::UnsizeView || op == ir::Op::SliceLength ||
         op == ir::Op::SliceBorrowRead || op == ir::Op::SliceBorrowMut ||
         op == ir::Op::ViewMut;
}
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
  auto contains = [](const Place &parent, const Place &child) {
    return parent.root == child.root &&
           parent.fields.size() <= child.fields.size() &&
           std::equal(parent.fields.begin(), parent.fields.end(),
                      child.fields.begin());
  };
  std::map<int, std::vector<int>> scopedLocals;
  std::vector<int> droppableLocals;
  std::vector<bool> droppable(function.locals.size());
  for (std::size_t i = 0; i < function.locals.size(); ++i) {
    const auto &local = function.locals[i];
    droppable[i] = types.needsDrop(local.type);
    if (i < function.parameters || local.storage == StorageDuration::Static)
      for (auto *bits : {&entry.definite, &entry.possible, &entry.ever})
        tree.set(*bits, tree.index({static_cast<int>(i), {}}), true);
    if (local.storage != StorageDuration::Static &&
        !(i < function.parameters && (local.mode == ParameterMode::Read ||
                                      local.mode == ParameterMode::Mut))) {
      scopedLocals[local.scope].push_back(static_cast<int>(i));
      if (droppable[i])
        droppableLocals.push_back(static_cast<int>(i));
    }
  }
  auto apply = [&](State &state, const ir::Instruction &instruction) {
    auto forget = [&](const Place &place) {
      for (auto &[sum, variants] : state.variants)
        if (contains(place, sum))
          variants = unknownVariants.at(sum);
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
            for (auto &[sum, variants] : state.variants)
              variants = unknownVariants.at(sum);
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
      if (auto found = scopedLocals.find(instruction.number);
          found != scopedLocals.end())
        for (auto local : found->second) {
          auto index = tree.index({local, {}});
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
  constexpr unsigned char definiteBit = 1, possibleBit = 2, everBit = 4,
                          movedBit = 8;
  using Demand = std::map<int, unsigned char>;
  const auto count = function.blocks.size();
  std::vector<Demand> reads(count), kills(count), relevant(count);
  std::vector<std::set<Place>> variantUses(count), variantReads(count),
      variantKills(count), variantRelevant(count);
  std::vector<bool> variantReset(count);
  std::vector<std::vector<int>> successors(count), predecessors(count);
  auto killed = [&](std::size_t b, int index) {
    auto found = kills[b].find(index);
    return found == kills[b].end() ? 0 : found->second;
  };
  auto variantKilled = [&](std::size_t b, const Place &place) {
    if (variantReset[b])
      return true;
    Place prefix{place.root, {}};
    for (std::size_t depth = 0;; ++depth) {
      if (variantKills[b].contains(prefix))
        return true;
      if (depth == place.fields.size())
        return false;
      prefix.fields.push_back(place.fields[depth]);
    }
  };
  for (std::size_t b = 0; b < count; ++b) {
    const auto &block = function.blocks[b];
    if (ir::continues(block.exit.kind) || block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.first);
    if (block.exit.kind == ir::Exit::Branch)
      successors[b].push_back(block.exit.second);
    for (auto next : successors[b])
      predecessors[next].push_back(static_cast<int>(b));
    auto observe = [&](int index, unsigned char bits) {
      for (auto child : tree.subtree(index))
        if (auto needed = static_cast<unsigned char>(bits & ~killed(b, child)))
          reads[b][child] |= needed;
    };
    auto kill = [&](int index, unsigned char bits) {
      for (auto child : tree.written(index))
        kills[b][child] |= bits;
    };
    for (const auto &instruction : block.instructions) {
      if (instruction.place.root >= 0) {
        const auto &local = function.locals[instruction.place.root];
        auto index = readsPlace(instruction.op) ||
                             instruction.op == ir::Op::Declare ||
                             instruction.op == ir::Op::Store ||
                             instruction.op == ir::Op::StorageWrite
                         ? tree.index(instruction.place)
                         : -1;
        if (readsPlace(instruction.op))
          observe(index, definiteBit | movedBit);
        Place prefix{instruction.place.root, {}};
        auto type = local.type;
        for (auto projection : instruction.place.fields) {
          if (types.isSum(type) && projection.kind == Projection::Kind::Field &&
              projection.index != 0) {
            variantUses[b].insert(prefix);
            if (!variantKilled(b, prefix))
              variantReads[b].insert(prefix);
          }
          if (projection.kind == Projection::Kind::Dereference)
            observe(tree.index(prefix), definiteBit | movedBit);
          if (instruction.op == ir::Op::Move && types.isProduct(type) &&
              (types.product(type).hasDestructor ||
               types.product(type).nativeCleanup != NativeCleanup::None))
            observe(tree.index(prefix), possibleBit);
          prefix.fields.push_back(projection);
          type = *projectedType(types, local.type, prefix.fields);
        }
        if (instruction.op == ir::Op::Declare &&
            droppable[instruction.place.root])
          observe(index, possibleBit);
        if (instruction.op == ir::Op::StorageWrite) {
          auto owner = instruction.place;
          owner.fields.pop_back();
          observe(tree.index(owner), definiteBit);
        }
        if ((instruction.op == ir::Op::Store ||
             instruction.op == ir::Op::StorageWrite) &&
            !local.mutableBinding && local.mode != ParameterMode::Mut &&
            local.mode != ParameterMode::Read)
          observe(index, everBit);
        if (instruction.op == ir::Op::Declare ||
            instruction.op == ir::Op::Store ||
            instruction.op == ir::Op::StorageWrite)
          kill(index, definiteBit | possibleBit | everBit | movedBit);
        else if (instruction.op == ir::Op::Move ||
                 instruction.op == ir::Op::DropPlace)
          kill(index, definiteBit | possibleBit | movedBit);
      }
      if (instruction.op == ir::Op::Store ||
          instruction.op == ir::Op::StorageWrite) {
        if (!variantReset[b])
          variantKills[b].insert(instruction.place);
      } else if (instruction.op == ir::Op::Call ||
                 instruction.op == ir::Op::IndirectCall ||
                 instruction.op == ir::Op::CatchCall) {
        for (auto operand : instruction.operands)
          if (operand.access == ir::Access::Mut ||
              (types.isView(operand.type) &&
               types.view(operand.type).mode == ParameterMode::Mut)) {
            const auto *definition = definitions[operand.id];
            if (!definition || definition->place.root < 0) {
              variantReset[b] = true;
              variantKills[b].clear();
              break;
            }
            if (!variantReset[b])
              variantKills[b].insert(definition->place);
          }
      }
      if (instruction.op == ir::Op::ScopeExit)
        if (auto found = scopedLocals.find(instruction.number);
            found != scopedLocals.end())
          for (auto local : found->second)
            kill(tree.index({local, {}}), definiteBit | possibleBit | movedBit);
    }
    if (block.exit.kind == ir::Exit::Return)
      for (auto local : droppableLocals)
        observe(tree.index({local, {}}), possibleBit);
  }
  std::deque<int> demands;
  std::vector<bool> queued(count, true);
  for (std::size_t b = count; b-- > 0;)
    demands.push_back(static_cast<int>(b));
  while (!demands.empty()) {
    auto b = demands.front();
    demands.pop_front();
    queued[b] = false;
    auto needed = reads[b];
    auto variants = variantReads[b];
    for (auto next : successors[b]) {
      for (auto [index, bits] : relevant[next])
        if (auto incoming =
                static_cast<unsigned char>(bits & ~killed(b, index)))
          needed[index] |= incoming;
      for (const auto &place : variantRelevant[next])
        if (!variantKilled(b, place))
          variants.insert(place);
    }
    if (needed == relevant[b] && variants == variantRelevant[b])
      continue;
    relevant[b] = std::move(needed);
    variantRelevant[b] = std::move(variants);
    for (auto previous : predecessors[b])
      if (!queued[previous]) {
        queued[previous] = true;
        demands.push_back(previous);
      }
  }
  reads.clear();
  kills.clear();
  variantReads.clear();
  variantKills.clear();
  variantReset.clear();
  std::vector<std::vector<std::pair<int, unsigned char>>> places(count);
  for (std::size_t b = 0; b < count; ++b) {
    places[b].assign(relevant[b].begin(), relevant[b].end());
    relevant[b].clear();
  }
  relevant.clear();
  struct Input {
    std::vector<unsigned char> places;
    std::map<Place, std::set<int>> variants;
  };
  std::vector<std::optional<Input>> inputs(count);
  auto placeBits = [&](const State &state, std::size_t index,
                       unsigned char mask) {
    return static_cast<unsigned char>(
        ((state.definite[index] ? definiteBit : 0) |
         (state.possible[index] ? possibleBit : 0) |
         (state.ever[index] ? everBit : 0) |
         (state.moved[index] ? movedBit : 0)) &
        mask);
  };
  inputs[0].emplace();
  for (const auto &place : variantRelevant[0])
    inputs[0]->variants.emplace(place, unknownVariants.at(place));
  inputs[0]->places.reserve(places[0].size());
  for (auto [index, bits] : places[0])
    inputs[0]->places.push_back(placeBits(entry, index, bits));
  State state = std::move(entry);
  auto restore = [&](std::size_t b) {
    state.variants.clear();
    auto restoreVariant = [&](const Place &place) {
      if (state.variants.contains(place))
        return;
      auto found = inputs[b]->variants.find(place);
      state.variants.emplace(place, found != inputs[b]->variants.end()
                                        ? found->second
                                        : unknownVariants.at(place));
    };
    for (const auto &place : variantUses[b])
      restoreVariant(place);
    for (auto next : successors[b])
      for (const auto &place : variantRelevant[next])
        restoreVariant(place);
    for (const auto &[place, variants] : inputs[b]->variants)
      state.variants.try_emplace(place, variants);
    std::size_t position = 0;
    for (auto [index, bits] : places[b]) {
      auto value = inputs[b]->places[position++];
      state.definite[index] = value & definiteBit;
      state.possible[index] = value & possibleBit;
      state.ever[index] = value & everBit;
      state.moved[index] = value & movedBit;
    }
  };
  queued.assign(count, false);
  queued[0] = true;
  std::deque<int> work{0};
  while (!work.empty()) {
    int block = work.front();
    work.pop_front();
    queued[block] = false;
    restore(block);
    auto &out = state;
    for (const auto &instruction : function.blocks[block].instructions)
      apply(out, instruction);
    const auto &exit = function.blocks[block].exit;
    const auto *condition =
        exit.kind == ir::Exit::Branch && exit.first != exit.second
            ? definitions[exit.value.id]
            : nullptr;
    if (condition && condition->op != ir::Op::VariantTest)
      condition = nullptr;
    for (auto next : successors[block]) {
      bool first = !inputs[next], changed = first;
      if (first) {
        inputs[next].emplace();
        inputs[next]->places.reserve(places[next].size());
      }
      auto &merged = *inputs[next];
      std::size_t position = 0;
      for (auto [index, mask] : places[next]) {
        auto incoming = placeBits(out, index, mask);
        if (first)
          merged.places.push_back(incoming);
        else {
          auto &previous = merged.places[position];
          auto bits = static_cast<unsigned char>(
              ((previous & incoming) & definiteBit) |
              ((previous | incoming) & ~definiteBit));
          changed |= previous != bits;
          previous = bits;
        }
        ++position;
      }
      for (const auto &place : variantRelevant[next]) {
        const auto &variants = out.variants.at(place);
        auto [found, inserted] = merged.variants.try_emplace(place, variants);
        auto &known = found->second;
        if (inserted) {
          if (condition && condition->place == place) {
            if (next == exit.first) {
              bool possible = known.contains(condition->number);
              known.clear();
              if (possible)
                known.insert(condition->number);
            } else
              known.erase(condition->number);
          }
          changed = true;
          continue;
        }
        if (known.size() == unknownVariants.at(place).size())
          continue;
        auto previous = known.size();
        if (!condition || condition->place != place)
          known.insert(variants.begin(), variants.end());
        else if (next == exit.first) {
          if (variants.contains(condition->number))
            known.insert(condition->number);
        } else
          for (auto variant : variants)
            if (variant != condition->number)
              known.insert(variant);
        changed |= previous != known.size();
      }
      if (changed) {
        if (!queued[next]) {
          queued[next] = true;
          work.push_back(next);
        }
      }
    }
  }
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    if (!inputs[b])
      continue;
    restore(b);
    for (const auto &instruction : function.blocks[b].instructions) {
      bool reference = false, writable = false, readOnly = false;
      bool invalidHandle = false;
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
            const auto &variants = state.variants.at(prefix);
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
            auto index = tree.index(prefix);
            if (!invalidHandle && !tree.all(state.definite, index)) {
              bool moved = tree.any(state.moved, index);
              diagnostics.error(moved ? "ownership" : "type", instruction.span,
                                moved ? "binding '" + tree.name(index) +
                                            "' may have been moved"
                                      : "view handle may be uninitialized");
              invalidHandle = true;
            }
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
      if (readsPlace(instruction.op)) {
        auto index = tree.index(instruction.place);
        if (!invalidHandle && !tree.all(state.definite, index)) {
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
                  ? "cannot move out of a viewed place; a `take` argument "
                    "consumes its value, so copy it into a binding first"
                  : "cannot move out of a viewed place");
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
      }
      if ((instruction.op == ir::Op::DropPlace ||
           instruction.op == ir::Op::ArrayTake) &&
          function.locals[instruction.place.root].storage ==
              StorageDuration::Static)
        diagnostics.error("ownership", instruction.span,
                          "cannot consume static storage");
      if (instruction.op == ir::Op::Declare &&
          droppable[instruction.place.root] &&
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
      if ((instruction.op == ir::Op::RawAddress &&
           types.pointer(instruction.result.type).mode == ParameterMode::Mut) ||
          instruction.op == ir::Op::BorrowMut ||
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
                            "mut view requires a mutable place");
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
      for (auto local : droppableLocals) {
        const auto &storage = function.locals[local];
        if (tree.any(state.possible, tree.index({local, {}})))
          diagnostics.error(
              "internal", storage.span,
              "owned storage reaches return without scope cleanup");
      }
  }
}
} // namespace
void initialization(const ir::Program &program, Diagnostics &diagnostics,
                    const ir::Program *prepared,
                    const std::vector<bool> *trusted) {
  for (std::size_t i = 0; i < program.functions.size(); ++i) {
    if (trusted && i < trusted->size() && (*trusted)[i])
      continue;
    const auto &function = program.functions[i];
    if (prepared && i < prepared->functions.size() &&
        function == prepared->functions[i])
      continue;
    valueOwnership(function, *program.types, diagnostics);
    checkFunction(function, *program.types, diagnostics);
  }
}
} // namespace mettle::analysis
