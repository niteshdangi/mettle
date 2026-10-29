#include "analysis/loans.h"
#include "analysis/origins.h"
#include "support/limits.h"
#include <algorithm>
#include <iterator>
#include <stdexcept>

namespace mettle::analysis {
namespace {
void join(Origins &a, const Origins &b) { a.insert(b.begin(), b.end()); }
void check(const ir::Function &function, const ir::Program &program,
           const EffectSummaries &summaries, Diagnostics &diagnostics) {
  if (function.blocks.empty())
    return;
  auto info = origins(function, program, summaries);
  auto overlapping = [&](const Place &first, const Place &second) {
    auto root = first.root >= 0 ? std::int64_t{first.root}
                                : -std::int64_t{first.root} - 1;
    if (root < 0 || static_cast<std::size_t>(root) >= function.locals.size())
      return overlaps(first, second);
    return overlaps(*program.types, function.locals[root].type, first, second);
  };
  for (const auto &[sources, span] : info.escapes)
    for (auto id : ancestors(sources, info.loans))
      for (const auto &target : info.loans.at(id).targets)
        if (target.place.root >= 0 &&
            function.locals[target.place.root].storage !=
                StorageDuration::Static)
          diagnostics.error(
              "ownership", span,
              "cannot store a view of local storage into caller-owned storage");
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
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch)
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
  std::vector<Origins> availableIn(count), availableOut(count), activeIn(count),
      activeOut(count);
  std::vector<Origins> pendingIn(count), pendingOut(count);
  bool changed;
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
  std::vector<std::vector<Origins>> availableAfter(count), activeBefore(count);
  std::vector<std::vector<Origins>> pendingBefore(count);
  for (std::size_t b = 0; b < count; ++b) {
    auto available = availableIn[b], active = activeIn[b],
         pending = pendingIn[b];
    for (std::size_t i = 0; i < info.points[b].size(); ++i) {
      activeBefore[b].push_back(active);
      pendingBefore[b].push_back(pending);
      join(available, info.points[b][i].defines);
      availableAfter[b].push_back(available);
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
  auto before = [&](Origins live, std::size_t b, std::size_t i) {
    Origins filtered;
    std::set_intersection(
        live.begin(), live.end(), availableAfter[b][i].begin(),
        availableAfter[b][i].end(), std::inserter(filtered, filtered.end()));
    for (auto id : info.points[b][i].defines)
      filtered.erase(id);
    join(filtered, info.points[b][i].uses);
    return ancestors(filtered, info.loans);
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
      for (std::size_t i = info.points[b].size(); i-- > 0;) {
        live = before(std::move(live), b, i);
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
    for (auto id : ancestors(info.returns[b], info.loans))
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
          diagnostics.error("ownership", {},
                            "returned view escapes local storage or its "
                            "declared input sources");
      }
    auto live = outputs[b];
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
      std::set_intersection(
          live.begin(), live.end(), availableAfter[b][i].begin(),
          availableAfter[b][i].end(), std::inserter(current, current.end()));
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
        }
      }
      bool conflict = false;
      bool exclusiveConflict = false;
      auto disjoint = [&](const Origins &authority, int other) {
        const auto relatives = ancestors({other}, info.loans);
        for (auto source : authority) {
          if (relatives.contains(source))
            continue;
          auto parents = ancestors({source}, info.loans);
          for (auto sibling : info.loans.at(source).disjointOutputs)
            if (relatives.contains(sibling) && !parents.contains(sibling))
              return true;
        }
        return false;
      };
      auto dynamicPayload = [&](const Origins &sources) {
        for (auto source : ancestors(sources, info.loans))
          if (info.loans.at(source).interiorPayload)
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
            if (authority.contains(id) || disjoint(authority, id))
              continue;
            for (const auto &referent : loan.targets)
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
            if (overlapping(dead, referent.place))
              conflict = true;
        for (auto dropped : point.drops) {
          auto authority = ancestors({dropped}, info.loans);
          if (authority.contains(id) || disjoint(authority, id))
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
      live = before(std::move(live), b, i);
    }
  }
}
} // namespace
void loans(const ir::Program &program, Diagnostics &diagnostics) {
  try {
    EffectSummaries summaries(program.functions.size());
    bool changed;
    std::size_t steps = 0;
    do {
      changed = false;
      for (std::size_t f = 0; f < program.functions.size(); ++f) {
        auto effects =
            origins(program.functions[f], program, summaries).effects;
        if (effects != summaries[f]) {
          if (++steps > limits::activeLoans)
            throw std::length_error("view effect analysis limit exceeded");
          summaries[f] = std::move(effects);
          changed = true;
        }
      }
    } while (changed);
    for (const auto &function : program.functions)
      check(function, program, summaries, diagnostics);
  } catch (const std::length_error &error) {
    diagnostics.error("limit", {}, error.what());
  }
}
} // namespace mettle::analysis
