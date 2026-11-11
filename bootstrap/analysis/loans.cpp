#include "analysis/loans.h"
#include "analysis/origins.h"
#include "support/limits.h"
#include <algorithm>
#include <iterator>
#include <map>
#include <stdexcept>
#include <tuple>
#include <utility>
#include <vector>

namespace mettle::analysis {
namespace {
void join(Origins &a, const Origins &b) { a.insert(b.begin(), b.end()); }
void check(const ir::Function &function, const ir::Program &program,
           const OriginInfo &info, Diagnostics &diagnostics) {
  if (function.blocks.empty())
    return;
  auto overlapping = [&](const Place &first, const Place &second) {
    auto root = first.root >= 0 ? std::int64_t{first.root}
                                : -std::int64_t{first.root} - 1;
    if (root < 0 || static_cast<std::size_t>(root) >= function.locals.size())
      return overlaps(first, second);
    return overlaps(*program.types, function.locals[root].type, first, second);
  };
  std::set<std::tuple<std::size_t, std::size_t, SourceId>> reported;
  for (const auto &[sources, span] : info.escapes) {
    // One report per escaping store, however many local loans back it.
    const auto escapes = [&] {
      for (auto id : ancestors(sources, info.loans))
        for (const auto &target : info.loans.at(id).targets)
          if (target.place.root >= 0 &&
              function.locals[target.place.root].storage !=
                  StorageDuration::Static)
            return true;
      return false;
    }();
    if (escapes && reported.emplace(span.begin, span.end, span.source).second)
      diagnostics.error(
          "ownership", span,
          "cannot store a view of local storage into caller-owned storage");
  }
  const auto count = function.blocks.size();
  std::vector<std::vector<int>> successors(count), predecessors(count);
  std::vector<bool> reachable(count);
  std::vector<int> work{0};
  while (!work.empty()) {
    auto b = work.back();
    work.pop_back();
    if (reachable[b])
      continue;
    reachable[b] = true;
    const auto &exit = function.blocks[b].exit;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      successors[b].push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      successors[b].push_back(exit.second);
    for (auto next : successors[b]) {
      predecessors[next].push_back(b);
      work.push_back(next);
    }
  }
  Origins external;
  for (const auto &[id, loan] : info.loans) {
    (void)loan;
    external.insert(id);
  }
  for (const auto &block : info.points)
    for (const auto &point : block)
      for (auto id : point.defines)
        external.erase(id);
  std::vector<std::set<int>> liveValues(count);
  bool changed;
  do {
    changed = false;
    for (std::size_t b = count; b-- > 0;) {
      if (!reachable[b])
        continue;
      std::set<int> live;
      auto use = [&](ir::Value value) {
        if (value.id >= 0 && !info.values[value.id].empty())
          live.insert(value.id);
      };
      for (auto next : successors[b]) {
        live.insert(liveValues[next].begin(), liveValues[next].end());
        for (const auto &instruction : function.blocks[next].instructions)
          if (instruction.op == ir::Op::Phi)
            for (std::size_t operand = 0; operand < instruction.operands.size();
                 ++operand)
              if (instruction.predecessors[operand] == static_cast<int>(b))
                use(instruction.operands[operand]);
      }
      use(function.blocks[b].exit.value);
      const auto &instructions = function.blocks[b].instructions;
      for (std::size_t i = instructions.size(); i-- > 0;) {
        const auto &instruction = instructions[i];
        live.erase(instruction.result.id);
        if (instruction.op != ir::Op::Phi)
          for (auto operand : instruction.operands)
            use(operand);
        if (instruction.op == ir::Op::IndirectCall)
          use(instruction.target);
      }
      if (liveValues[b] != live) {
        liveValues[b] = std::move(live);
        changed = true;
      }
    }
  } while (changed);
  std::vector<Origins> availableIn(count), availableOut(count), activeIn(count),
      activeOut(count);
  std::vector<Origins> heldIn(count);
  for (std::size_t b = 0; b < count; ++b) {
    auto &held = heldIn[b];
    held = external;
    join(held, info.storedIn[b]);
    for (auto value : liveValues[b])
      for (const auto &[path, sources] : info.values[value]) {
        (void)path;
        join(held, sources);
      }
    for (const auto &instruction : function.blocks[b].instructions)
      if (instruction.op == ir::Op::Phi)
        for (auto operand : instruction.operands)
          for (const auto &[path, sources] : info.values[operand.id]) {
            (void)path;
            join(held, sources);
          }
    held = ancestors(held, info.loans);
  }
  std::vector<Origins> pendingIn(count), pendingOut(count);
  do {
    changed = false;
    for (std::size_t b = 0; b < count; ++b) {
      if (!reachable[b])
        continue;
      Origins available = b == 0 ? external : Origins{}, active, pending;
      for (auto p : predecessors[b]) {
        join(available, availableOut[p]);
        join(active, activeOut[p]);
        join(pending, pendingOut[p]);
      }
      availableIn[b] = available;
      activeIn[b] = active;
      pendingIn[b] = pending;
      for (std::size_t i = 0; i < info.points[b].size(); ++i) {
        join(available, info.points[b][i].defines);
        const auto &instruction = function.blocks[b].instructions[i];
        if (instruction.op == ir::Op::ReserveMut)
          for (auto id : info.points[b][i].defines) {
            active.erase(id);
            pending.insert(id);
          }
        if (instruction.op == ir::Op::Activate)
          for (auto operand : instruction.operands)
            for (const auto &[path, sources] : info.values[operand.id]) {
              (void)path;
              join(active, sources);
              for (auto id : sources)
                pending.erase(id);
            }
      }
      if (availableOut[b] != available || activeOut[b] != active ||
          pendingOut[b] != pending)
        changed = true;
      availableOut[b] = std::move(available);
      activeOut[b] = std::move(active);
      pendingOut[b] = std::move(pending);
    }
  } while (changed);
  for (std::size_t b = 0; b < count; ++b) {
    Origins available;
    std::set_intersection(availableIn[b].begin(), availableIn[b].end(),
                          heldIn[b].begin(), heldIn[b].end(),
                          std::inserter(available, available.end()));
    availableIn[b] = std::move(available);
    availableOut[b] = availableIn[b];
    for (const auto &point : info.points[b])
      join(availableOut[b], point.defines);
  }
  std::vector<std::vector<Origins>> activeBefore(count);
  std::vector<std::vector<Origins>> pendingBefore(count);
  for (std::size_t b = 0; b < count; ++b) {
    auto available = availableIn[b], active = activeIn[b],
         pending = pendingIn[b];
    for (std::size_t i = 0; i < info.points[b].size(); ++i) {
      activeBefore[b].push_back(active);
      pendingBefore[b].push_back(pending);
      join(available, info.points[b][i].defines);
      const auto &instruction = function.blocks[b].instructions[i];
      if (instruction.op == ir::Op::ReserveMut)
        for (auto id : info.points[b][i].defines) {
          active.erase(id);
          pending.insert(id);
        }
      if (instruction.op == ir::Op::Activate)
        for (auto operand : instruction.operands)
          for (const auto &[path, sources] : info.values[operand.id]) {
            (void)path;
            join(active, sources);
            for (auto id : sources)
              pending.erase(id);
          }
    }
  }
  std::vector<std::map<int, std::size_t>> definitionCounts(count);
  for (std::size_t b = 0; b < count; ++b)
    for (const auto &point : info.points[b])
      for (auto id : point.defines)
        ++definitionCounts[b][id];
  // Rebuild point availability backward from the fixed-point block output,
  // instead of copying a full loan set into a snapshot for every instruction.
  auto rewindAvailability = [&](Origins &available,
                                std::map<int, std::size_t> &remaining,
                                std::size_t b, std::size_t i) {
    for (auto id : info.points[b][i].defines) {
      auto found = remaining.find(id);
      if (found != remaining.end() && --found->second == 0 &&
          !availableIn[b].contains(id))
        available.erase(id);
    }
  };
  auto retainAvailable = [](Origins &live, const Origins &available) {
    auto loan = live.begin();
    auto candidate = available.begin();
    while (loan != live.end() && candidate != available.end()) {
      if (*loan < *candidate)
        loan = live.erase(loan);
      else if (*candidate < *loan)
        ++candidate;
      else {
        ++loan;
        ++candidate;
      }
    }
    live.erase(loan, live.end());
  };
  auto before = [&](Origins live, const Origins &available, std::size_t b,
                    std::size_t i) {
    retainAvailable(live, available);
    for (auto id : info.points[b][i].defines)
      live.erase(id);
    join(live, info.points[b][i].uses);
    return ancestors(live, info.loans);
  };
  std::vector<Origins> inputs(count), outputs(count);
  do {
    changed = false;
    for (std::size_t b = count; b-- > 0;) {
      if (!reachable[b])
        continue;
      Origins live = info.returns[b];
      for (auto next : successors[b])
        join(live, inputs[next]);
      outputs[b] = ancestors(live, info.loans);
      Origins available = availableOut[b];
      auto remaining = definitionCounts[b];
      for (std::size_t i = info.points[b].size(); i-- > 0;) {
        live = before(std::move(live), available, b, i);
        rewindAvailability(available, remaining, b, i);
        if (live.size() > limits::activeLoans) {
          diagnostics.error("limit", function.blocks[b].instructions[i].span,
                            "active loan limit exceeded");
          return;
        }
      }
      if (inputs[b] != live) {
        inputs[b] = std::move(live);
        changed = true;
      }
    }
  } while (changed);
  for (std::size_t b = 0; b < count; ++b) {
    if (!reachable[b])
      continue;
    for (auto id : strongAncestors(info.returns[b], info.loans))
      for (const auto &target : info.loans.at(id).targets) {
        if (target.place.root >= 0 &&
            function.locals[target.place.root].storage ==
                StorageDuration::Static)
          continue;
        auto source = info.externalSources.find(target.place.root);
        if (source == info.externalSources.end() ||
            std::find(function.resultSources.begin(),
                      function.resultSources.end(),
                      static_cast<std::size_t>(source->second)) ==
                function.resultSources.end())
          diagnostics.error("ownership", function.blocks[b].exit.span,
                            "returned view escapes local storage or its "
                            "declared input sources");
      }
    auto live = outputs[b];
    Origins available = availableOut[b];
    auto remaining = definitionCounts[b];
    for (std::size_t i = info.points[b].size(); i-- > 0;) {
      const auto &instruction = function.blocks[b].instructions[i];
      const auto &point = info.points[b][i];
      if (instruction.op == ir::Op::Call ||
          instruction.op == ir::Op::IndirectCall ||
          instruction.op == ir::Op::CatchCall)
        for (auto operand : instruction.operands)
          for (const auto &[path, sources] : info.values[operand.id]) {
            (void)path;
            for (auto id : sources)
              if (info.loans.at(id).reserved &&
                  (pendingBefore[b][i].contains(id) ||
                   !activeBefore[b][i].contains(id)))
                diagnostics.error("internal", instruction.span,
                                  "receiver reservation was not activated on "
                                  "every incoming path");
          }
      Origins current;
      for (auto id : live)
        if (available.contains(id))
          current.insert(id);
      bool activation = instruction.op == ir::Op::Activate;
      bool reservation = instruction.op == ir::Op::ReserveMut;
      bool read = instruction.op == ir::Op::Load ||
                  instruction.op == ir::Op::VariantTest ||
                  instruction.op == ir::Op::BorrowRead ||
                  instruction.op == ir::Op::ViewRead || reservation;
      read |= instruction.op == ir::Op::ArrayBorrowRead;
      read |= instruction.op == ir::Op::SliceBorrowRead;
      read |= instruction.op == ir::Op::EraseView &&
              program.types->view(instruction.result.type).mode ==
                  ParameterMode::Read;
      bool write = instruction.op == ir::Op::Move ||
                   instruction.op == ir::Op::DropPlace ||
                   instruction.op == ir::Op::Store ||
                   instruction.op == ir::Op::StorageWrite ||
                   instruction.op == ir::Op::BorrowMut ||
                   instruction.op == ir::Op::ViewMut || activation;
      write |= instruction.op == ir::Op::ArrayBorrowMut;
      write |= instruction.op == ir::Op::SliceBorrowMut;
      write |= instruction.op == ir::Op::ArrayTake;
      write |= instruction.op == ir::Op::EraseView &&
               program.types->view(instruction.result.type).mode ==
                   ParameterMode::Mut;
      read |= instruction.op == ir::Op::UnsizeView &&
              program.types->view(instruction.result.type).mode ==
                  ParameterMode::Read;
      write |= instruction.op == ir::Op::UnsizeView &&
               program.types->view(instruction.result.type).mode ==
                   ParameterMode::Mut;
      read |= instruction.op == ir::Op::ErasedUpcast &&
              program.types->view(instruction.result.type).mode ==
                  ParameterMode::Read;
      write |= instruction.op == ir::Op::ErasedUpcast &&
               program.types->view(instruction.result.type).mode ==
                   ParameterMode::Mut;
      auto targets = point.targets;
      Origins activating;
      if (activation) {
        for (auto operand : instruction.operands)
          for (const auto &[path, sources] : info.values[operand.id]) {
            (void)path;
            join(activating, sources);
          }
        for (auto id : activating) {
          if (!info.loans.at(id).reserved || activeBefore[b][i].contains(id)) {
            diagnostics.error("internal", instruction.span,
                              "invalid receiver reservation activation");
            continue;
          }
          targets.insert(info.loans.at(id).targets.begin(),
                         info.loans.at(id).targets.end());
          for (auto target : info.loans.at(id).frozen) {
            target.authority.insert(id);
            targets.insert(std::move(target));
          }
        }
      }
      bool conflict = false;
      bool exclusiveConflict = false;
      auto dynamicPayload = [&](const Origins &sources) {
        for (auto source : ancestors(sources, info.loans))
          if (info.loans.at(source).interiorPayload)
            return true;
        return false;
      };
      // A loan that only keeps its container borrow unavailable does not
      // borrow the container's storage, so ending that storage is harmless
      // unless some other live loan depends on the borrow itself.
      auto shadowed = [&](int id) {
        for (auto other : current)
          if (other != id) {
            Origins start;
            for (auto parent : info.loans.at(other).parents)
              if (!info.loans.at(other).borrowed.contains(parent))
                start.insert(parent);
            if (strongAncestors(start, info.loans).contains(id))
              return false;
          }
        for (auto other : current)
          if (info.loans.at(other).borrowed.contains(id))
            return true;
        return false;
      };
      bool interiorRead = false;
      if (read && !write && instruction.place.root >= 0) {
        auto type = projectedType(*program.types,
                                  function.locals[instruction.place.root].type,
                                  instruction.place.fields);
        interiorRead =
            type && program.types->isProduct(*type) &&
            (program.types->product(*type).kind == AggregateKind::Cell ||
             program.types->product(*type).kind == AggregateKind::RefCell);
      }
      for (auto id : current) {
        bool priorConflict = conflict;
        const auto &loan = info.loans.at(id);
        bool introduced = point.defines.contains(id) || activating.contains(id);
        bool exclusive = loan.mode == ParameterMode::Mut &&
                         (!loan.reserved || activeBefore[b][i].contains(id));
        if ((read || write) && !introduced)
          for (const auto &access : targets) {
            auto authority = ancestors(access.authority, info.loans);
            if (authority.contains(id) ||
                disjointLoans(authority, id, info.loans))
              continue;
            auto referents = loan.targets;
            referents.insert(loan.frozen.begin(), loan.frozen.end());
            for (const auto &referent : referents)
              if (overlapping(access.place, referent.place) &&
                  (write || exclusive ||
                   (reservation && loan.mode == ParameterMode::Mut))) {
                // A shared cell handle freezes its lifetime, not its payload.
                // Only a checked guard can authorize the interior write.
                bool interior = loan.interiorRoot &&
                                dynamicPayload(access.authority) &&
                                containsPlace(referent.place, access.place);
                interior |= interiorRead && dynamicPayload({id}) &&
                            containsPlace(access.place, referent.place);
                if (!interior)
                  conflict = true;
              }
          }
        for (const auto &dead : point.dead)
          for (const auto &referent : loan.targets)
            if (overlapping(dead, referent.place) && !shadowed(id))
              conflict = true;
        for (auto dropped : point.drops) {
          auto authority = ancestors({dropped}, info.loans);
          if (authority.contains(id) ||
              disjointLoans(authority, id, info.loans))
            continue;
          const auto &destructorLoan = info.loans.at(dropped);
          for (const auto &access : destructorLoan.targets)
            for (const auto &referent : loan.targets)
              if (overlapping(access.place, referent.place) &&
                  (destructorLoan.mode == ParameterMode::Mut || exclusive) &&
                  !(destructorLoan.interiorRoot && dynamicPayload({id}) &&
                    containsPlace(access.place, referent.place)))
                conflict = true;
        }
        for (auto moved : point.movedViews)
          if (id != moved && ancestors({id}, info.loans).contains(moved))
            conflict = true;
        if (conflict && !priorConflict)
          exclusiveConflict = loan.mode == ParameterMode::Mut;
      }
      if (conflict)
        diagnostics.error(
            "ownership", instruction.span,
            std::string("access or storage lifetime conflicts with a live ") +
                (exclusiveConflict ? "exclusive" : "read") + " loan");
      live = before(std::move(live), available, b, i);
      rewindAvailability(available, remaining, b, i);
    }
  }
}
// Post-order position of every function in the call graph, callees first.
std::vector<std::size_t> calleeFirstRank(const ir::Program &program) {
  const auto count = program.functions.size();
  std::vector<std::size_t> rank(count, 0);
  std::vector<bool> seen(count, false);
  std::size_t next = 0;
  for (std::size_t root = 0; root < count; ++root) {
    if (seen[root])
      continue;
    // Each frame is a function and the position of its next instruction.
    std::vector<std::tuple<std::size_t, std::size_t, std::size_t>> stack;
    seen[root] = true;
    stack.emplace_back(root, 0, 0);
    while (!stack.empty()) {
      auto &[f, block, instruction] = stack.back();
      const auto &blocks = program.functions[f].blocks;
      std::size_t callee = count;
      while (block < blocks.size() && callee == count) {
        if (instruction >= blocks[block].instructions.size()) {
          ++block;
          instruction = 0;
          continue;
        }
        const auto &current = blocks[block].instructions[instruction++];
        if ((current.op == ir::Op::Call || current.op == ir::Op::IndirectCall ||
             current.op == ir::Op::CatchCall) &&
            current.callee >= 0 &&
            static_cast<std::size_t>(current.callee) < count &&
            !seen[static_cast<std::size_t>(current.callee)])
          callee = static_cast<std::size_t>(current.callee);
      }
      if (callee != count) {
        seen[callee] = true;
        stack.emplace_back(callee, 0, 0);
      } else {
        rank[f] = next++;
        stack.pop_back();
      }
    }
  }
  return rank;
}
} // namespace
LoanResults loans(const ir::Program &program, Diagnostics &diagnostics,
                  const ir::Program *prepared, const LoanResults *previous) {
  LoanResults result;
  try {
    EffectSummaries summaries(program.functions.size());
    std::vector<std::set<std::size_t>> dependents(program.functions.size());
    std::vector<bool> reusable(program.functions.size(), false);
    if (prepared && previous &&
        previous->effects.size() == prepared->functions.size()) {
      for (std::size_t f = 0; f < program.functions.size(); ++f) {
        const auto &function = program.functions[f];
        reusable[f] = f < prepared->functions.size() &&
                      function == prepared->functions[f] &&
                      std::none_of(
                          function.locals.begin(), function.locals.end(),
                          [](const auto &local) {
                            return local.storage == StorageDuration::Static;
                          });
        for (const auto &block : function.blocks)
          for (const auto &instruction : block.instructions)
            if (instruction.callee >= 0)
              dependents.at(instruction.callee).insert(f);
      }
      std::vector<std::size_t> changed;
      for (std::size_t f = 0; f < reusable.size(); ++f)
        if (!reusable[f])
          changed.push_back(f);
      while (!changed.empty()) {
        auto f = changed.back();
        changed.pop_back();
        for (auto dependent : dependents[f])
          if (reusable[dependent]) {
            reusable[dependent] = false;
            changed.push_back(dependent);
          }
      }
      for (std::size_t f = 0; f < reusable.size(); ++f)
        if (reusable[f]) {
          summaries.slot(f) = previous->effects[f];
          ++result.reusedFunctions;
        }
    }
    // Analyzing callees before callers lets most summaries settle on the first
    // visit instead of re-running every caller after each callee changes.
    const auto rank = calleeFirstRank(program);
    std::set<std::pair<std::size_t, std::size_t>> pending;
    for (std::size_t f = 0; f < program.functions.size(); ++f)
      if (!reusable[f])
        pending.emplace(rank[f], f);
    std::vector<OriginInfo> final(program.functions.size());
    std::size_t steps = 0;
    while (!pending.empty()) {
      auto f = pending.begin()->second;
      pending.erase(pending.begin());
      std::set<std::size_t> reads;
      summaries.record(&reads);
      auto info = origins(program.functions[f], program, summaries);
      summaries.record(nullptr);
      for (auto callee : reads)
        dependents[callee].insert(f);
      const bool stable = info.effects == summaries.slot(f);
      // The last run of a function saw its final callee summaries, so it is
      // the analysis the ownership check needs.
      final[f] = std::move(info);
      if (!stable) {
        if (++steps > limits::activeLoans)
          throw std::length_error("view effect analysis limit exceeded");
        summaries.slot(f) = final[f].effects;
        for (auto dependent : dependents[f])
          pending.emplace(rank[dependent], dependent);
      }
    }
    for (std::size_t f = 0; f < program.functions.size(); ++f)
      if (!reusable[f])
        check(program.functions[f], program, final[f], diagnostics);
    if (diagnostics.empty()) {
      result.effects.reserve(program.functions.size());
      for (std::size_t f = 0; f < program.functions.size(); ++f)
        result.effects.push_back(std::move(summaries.slot(f)));
    }
  } catch (const std::length_error &error) {
    diagnostics.error("limit", {}, error.what());
  }
  return result;
}
} // namespace mettle::analysis
