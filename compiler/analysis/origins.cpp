#include "analysis/origins.h"
#include "support/limits.h"
#include <algorithm>
#include <deque>
#include <functional>
#include <optional>
#include <stdexcept>

namespace mettle::analysis {
namespace {
using Memory = std::map<Place, Origins>;
void join(Origins &a, const Origins &b) { a.insert(b.begin(), b.end()); }
void join(ViewOrigins &a, const ViewOrigins &b) {
  for (const auto &[path, sources] : b)
    join(a[path], sources);
}
void join(Memory &a, const Memory &b) {
  for (const auto &[path, sources] : b)
    join(a[path], sources);
}
Origins flatten(const ViewOrigins &value) {
  Origins result;
  for (const auto &[path, sources] : value)
    join(result, sources);
  return result;
}
bool prefix(const Place &parent, const Place &child) {
  return parent.root == child.root &&
         parent.fields.size() <= child.fields.size() &&
         std::equal(parent.fields.begin(), parent.fields.end(),
                    child.fields.begin());
}
std::vector<std::pair<ViewPath, Type>> viewPaths(Type type,
                                                 const TypeStore &types) {
  std::vector<std::pair<ViewPath, Type>> result;
  std::function<void(Type, ViewPath)> visit = [&](Type current, ViewPath path) {
    if (types.isView(current)) {
      if (result.size() >= limits::activeLoans)
        throw std::length_error("view projection limit exceeded");
      result.emplace_back(std::move(path), current);
      return;
    }
    if (!types.isProduct(current))
      return;
    const auto &fields = types.product(current).fields;
    for (std::size_t i = 0; i < fields.size(); ++i) {
      auto child = path;
      child.push_back(Projection::field(static_cast<std::uint32_t>(i)));
      visit(fields[i].type, std::move(child));
    }
  };
  visit(type, {});
  return result;
}
bool borrowed(ir::Op op) {
  return op == ir::Op::BorrowRead || op == ir::Op::BorrowMut ||
         op == ir::Op::ReserveMut || op == ir::Op::ViewRead ||
         op == ir::Op::ViewMut;
}
bool destructorUses(const TypeStore &types, Type type, const ViewPath &path) {
  for (auto projection : path) {
    if (!types.isProduct(type))
      return false;
    if (types.product(type).hasDestructor)
      return true;
    type = types.product(type).fields.at(projection.index).type;
  }
  return types.isProduct(type) && types.product(type).hasDestructor;
}
std::set<Place> overwrites(const ir::Function &function,
                           const std::vector<std::vector<Point>> &points) {
  using Written = std::set<Place>;
  std::vector<std::optional<Written>> inputs(function.blocks.size()),
      outputs(function.blocks.size());
  inputs[0] = Written{};
  std::deque<int> work{0};
  while (!work.empty()) {
    int block = work.front();
    work.pop_front();
    auto written = *inputs[block];
    for (const auto &point : points[block])
      written.insert(point.overwrites.begin(), point.overwrites.end());
    if (outputs[block] && *outputs[block] == written)
      continue;
    outputs[block] = written;
    const auto &exit = function.blocks[block].exit;
    std::vector<int> successors;
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch)
      successors.push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      successors.push_back(exit.second);
    for (int successor : successors) {
      Written merged = written;
      if (inputs[successor]) {
        merged.clear();
        std::set_intersection(inputs[successor]->begin(),
                              inputs[successor]->end(), written.begin(),
                              written.end(),
                              std::inserter(merged, merged.end()));
      }
      if (!inputs[successor] || *inputs[successor] != merged) {
        inputs[successor] = std::move(merged);
        work.push_back(successor);
      }
    }
  }
  std::optional<Written> result;
  for (std::size_t block = 0; block < function.blocks.size(); ++block)
    if (outputs[block] &&
        function.blocks[block].exit.kind == ir::Exit::Return) {
      if (!result)
        result = *outputs[block];
      else {
        Written merged;
        std::set_intersection(result->begin(), result->end(),
                              outputs[block]->begin(), outputs[block]->end(),
                              std::inserter(merged, merged.end()));
        result = std::move(merged);
      }
    }
  return result.value_or(Written{});
}
} // namespace
Origins ancestors(const Origins &origins, const std::map<int, Loan> &loans) {
  Origins result = origins;
  std::vector<int> work(origins.begin(), origins.end());
  while (!work.empty()) {
    int id = work.back();
    work.pop_back();
    auto found = loans.find(id);
    if (found == loans.end())
      continue;
    for (auto parent : found->second.parents)
      if (result.insert(parent).second)
        work.push_back(parent);
  }
  return result;
}

OriginInfo origins(const ir::Function &function, const ir::Program &program,
                   const EffectSummaries &summaries) {
  const auto &types = *program.types;
  OriginInfo result;
  if (function.blocks.empty())
    return result;
  result.points.resize(function.blocks.size());
  result.returns.resize(function.blocks.size());
  result.values.resize(function.values);
  int synthetic = function.values, external = -1;
  std::vector<Place> bases(function.locals.size());
  Memory entry;
  std::map<Place, int> externalContents;
  auto externalLoan = [&](const Place &key, Type type, int parameter) {
    if (auto found = externalContents.find(key);
        found != externalContents.end())
      return found->second;
    if (result.loans.size() >= limits::activeLoans)
      throw std::length_error("view origin limit exceeded");
    int id = synthetic++;
    Loan loan;
    loan.mode = types.view(type).mode;
    loan.parameter = parameter;
    int root = external--;
    result.externalSources[root] = parameter;
    auto relative = key.root >= 0 ? Place{key.root, {}}
                                  : result.externalPlaces.at(key.root);
    relative.fields.insert(relative.fields.end(), key.fields.begin(),
                           key.fields.end());
    relative.fields.push_back(Projection::dereference());
    result.externalPlaces[root] = std::move(relative);
    loan.targets.insert(Target{{root, {}}, {id}});
    result.loans.emplace(id, std::move(loan));
    externalContents.emplace(key, id);
    return id;
  };
  for (std::size_t p = 0; p < function.locals.size(); ++p) {
    bool reference = p < function.parameters &&
                     (function.locals[p].mode == ParameterMode::Read ||
                      function.locals[p].mode == ParameterMode::Mut);
    bases[p] = {reference ? external-- : static_cast<int>(p), {}};
    if (reference)
      result.externalSources[bases[p].root] = static_cast<int>(p);
    if (reference)
      result.externalPlaces[bases[p].root] = {static_cast<int>(p), {}};
    if (p >= function.parameters)
      continue;
    for (const auto &[path, type] : viewPaths(function.locals[p].type, types)) {
      auto key = bases[p];
      key.fields = path;
      entry[key].insert(externalLoan(key, type, static_cast<int>(p)));
    }
  }
  std::vector<std::vector<std::vector<int>>> created(function.blocks.size());
  std::vector<std::vector<std::map<Place, int>>> effectIds(
      function.blocks.size());
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    result.points[b].resize(function.blocks[b].instructions.size());
    created[b].resize(function.blocks[b].instructions.size());
    effectIds[b].resize(function.blocks[b].instructions.size());
    for (std::size_t i = 0; i < function.blocks[b].instructions.size(); ++i) {
      const auto &instruction = function.blocks[b].instructions[i];
      if (borrowed(instruction.op))
        created[b][i].push_back(instruction.result.id);
      else if (instruction.op == ir::Op::Call &&
               types.containsViews(instruction.result.type))
        for (const auto &path : viewPaths(instruction.result.type, types)) {
          (void)path;
          created[b][i].push_back(synthetic++);
        }
      if (instruction.op == ir::Op::Call || instruction.op == ir::Op::CatchCall)
        for (const auto &[destination, sources] :
             summaries[instruction.callee].writes) {
          (void)sources;
          effectIds[b][i].emplace(destination, synthetic++);
        }
    }
  }
  std::vector<std::vector<int>> predecessors(function.blocks.size());
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    const auto &exit = function.blocks[b].exit;
    if (exit.kind == ir::Exit::Jump || exit.kind == ir::Exit::Branch)
      predecessors[exit.first].push_back(static_cast<int>(b));
    if (exit.kind == ir::Exit::Branch)
      predecessors[exit.second].push_back(static_cast<int>(b));
  }
  std::vector<Memory> outputs(function.blocks.size());
  bool changed;
  do {
    changed = false;
    for (std::size_t b = 0; b < function.blocks.size(); ++b) {
      Memory memory = b == 0 ? entry : Memory{};
      for (auto predecessor : predecessors[b])
        join(memory, outputs[predecessor]);
      auto resolve = [&](const Place &raw, Origins &uses) {
        std::set<Target> targets{{bases.at(raw.root), {}}};
        auto currentType = function.locals[raw.root].type;
        for (auto projection : raw.fields) {
          if (projection.kind == Projection::Kind::Field) {
            currentType =
                types.product(currentType).fields.at(projection.index).type;
            std::set<Target> next;
            for (auto target : targets) {
              target.place.fields.push_back(projection);
              next.insert(std::move(target));
            }
            targets = std::move(next);
          } else {
            std::set<Target> next;
            for (const auto &target : targets) {
              auto found = memory.find(target.place);
              Origins sources =
                  found == memory.end() ? Origins{} : found->second;
              if (sources.empty() && target.place.root < 0) {
                int parameter = raw.root < static_cast<int>(function.parameters)
                                    ? raw.root
                                    : -1;
                for (auto id : ancestors(target.authority, result.loans))
                  if (result.loans.at(id).parameter >= 0)
                    parameter = result.loans.at(id).parameter;
                sources.insert(
                    externalLoan(target.place, currentType, parameter));
              }
              join(uses, sources);
              for (auto id : sources) {
                auto loan = result.loans.find(id);
                if (loan == result.loans.end())
                  continue;
                for (auto referent : loan->second.targets) {
                  referent.authority.insert(id);
                  join(referent.authority, target.authority);
                  next.insert(std::move(referent));
                }
              }
            }
            targets = std::move(next);
            currentType = types.view(currentType).payload;
          }
        }
        return targets;
      };
      auto relative = [&](const Place &place) {
        auto source = result.externalPlaces.at(place.root);
        source.fields.insert(source.fields.end(), place.fields.begin(),
                             place.fields.end());
        if (source.fields.size() > limits::typeDepth)
          throw std::length_error("view effect projection limit exceeded");
        return source;
      };
      auto record = [&](const std::set<Target> &targets,
                        const ViewOrigins &value, Span span) {
        for (const auto &target : targets) {
          if (target.place.root >= 0)
            continue;
          for (const auto &[path, sources] : value) {
            auto destination = relative(target.place);
            destination.fields.insert(destination.fields.end(), path.begin(),
                                      path.end());
            for (auto id : sources)
              for (const auto &source : result.loans.at(id).targets)
                if (source.place.root < 0)
                  result.effects.writes[destination].insert(
                      relative(source.place));
            for (auto id : ancestors(sources, result.loans))
              for (const auto &source : result.loans.at(id).targets)
                if (source.place.root < 0)
                  result.effects.writeDependencies[destination].insert(
                      relative(source.place));
            result.escapes.emplace_back(sources, span);
          }
        }
      };
      auto drop = [&](const Place &owner, std::size_t instructionIndex,
                      Span span, Origins &uses) {
        std::function<void(Place, Type)> visit = [&](Place place, Type type) {
          if (!types.isProduct(type))
            return;
          const auto &product = types.product(type);
          if (product.hasDestructor) {
            const auto &effects = summaries.at(product.destructor);
            auto actual = [&](const Place &formal) {
              auto raw = place;
              raw.fields.insert(raw.fields.end(), formal.fields.begin(),
                                formal.fields.end());
              return raw;
            };
            for (const auto &[destination, sources] : effects.writes) {
              auto raw = actual(destination);
              auto &ids = effectIds[b][instructionIndex];
              auto [found, inserted] = ids.try_emplace(raw, synthetic);
              if (inserted)
                ++synthetic;
              int id = found->second;
              auto &loan = result.loans[id];
              auto oldTargets = loan.targets.size();
              auto oldParents = loan.parents.size();
              loan.mode =
                  types
                      .view(*projectedType(
                          types, function.locals[raw.root].type, raw.fields))
                      .mode;
              for (const auto &source : sources)
                for (const auto &target : resolve(actual(source), uses)) {
                  loan.targets.insert(target);
                  join(loan.parents, target.authority);
                }
              if (auto dependencies =
                      effects.writeDependencies.find(destination);
                  dependencies != effects.writeDependencies.end())
                for (const auto &source : dependencies->second)
                  for (const auto &target : resolve(actual(source), uses))
                    join(loan.parents, target.authority);
              auto destinations = resolve(raw, uses);
              for (const auto &target : destinations)
                memory[target.place].insert(id);
              record(destinations, {{{}, {id}}}, span);
              result.points[b][instructionIndex].defines.insert(id);
              if (oldTargets != loan.targets.size() ||
                  oldParents != loan.parents.size())
                changed = true;
            }
          }
          for (std::size_t field = 0; field < product.fields.size(); ++field) {
            auto child = place;
            child.fields.push_back(
                Projection::field(static_cast<std::uint32_t>(field)));
            visit(std::move(child), product.fields[field].type);
          }
        };
        visit(owner, *projectedType(types, function.locals[owner.root].type,
                                    owner.fields));
      };
      for (std::size_t i = 0; i < function.blocks[b].instructions.size(); ++i) {
        const auto &instruction = function.blocks[b].instructions[i];
        auto &point = result.points[b][i];
        point.overwrites.clear();
        ViewOrigins value;
        Origins uses;
        for (auto operand : instruction.operands)
          join(uses, flatten(result.values[operand.id]));
        if (instruction.op == ir::Op::Call ||
            instruction.op == ir::Op::CatchCall) {
          std::vector<int> work(uses.begin(), uses.end());
          while (!work.empty()) {
            auto id = work.back();
            work.pop_back();
            for (const auto &target : result.loans.at(id).targets)
              for (const auto &[location, contents] : memory)
                if (prefix(target.place, location))
                  for (auto content : contents)
                    if (uses.insert(content).second)
                      work.push_back(content);
          }
        }
        std::set<Target> targets;
        if (instruction.place.root >= 0)
          targets = resolve(instruction.place, uses);
        point.targets.insert(targets.begin(), targets.end());
        if (instruction.op == ir::Op::Load || instruction.op == ir::Op::Move) {
          for (const auto &[path, type] :
               viewPaths(instruction.result.type, types)) {
            for (const auto &target : targets) {
              auto key = target.place;
              key.fields.insert(key.fields.end(), path.begin(), path.end());
              if (key.root < 0 && memory[key].empty())
                memory[key].insert(externalLoan(
                    key, type, result.externalSources.at(key.root)));
              join(value[path], memory[key]);
            }
          }
          join(uses, flatten(value));
          if (instruction.op == ir::Op::Move) {
            join(point.movedViews, flatten(value));
            for (const auto &target : targets)
              for (auto it = memory.begin(); it != memory.end();)
                if (prefix(target.place, it->first))
                  it = memory.erase(it);
                else
                  ++it;
          }
        } else if (instruction.op == ir::Op::Store) {
          drop(instruction.place, i, instruction.span, uses);
          const auto &rhs = result.values[instruction.operands[0].id];
          record(targets, rhs, instruction.span);
          if (targets.size() == 1)
            for (const auto &[path, type] :
                 viewPaths(instruction.operands[0].type, types)) {
              (void)type;
              auto key = targets.begin()->place;
              key.fields.insert(key.fields.end(), path.begin(), path.end());
              point.overwrites.insert(std::move(key));
            }
          for (const auto &target : targets) {
            for (auto it = memory.begin(); it != memory.end();)
              if (prefix(target.place, it->first) && targets.size() == 1) {
                auto path = ViewPath(it->first.fields.begin() +
                                         target.place.fields.size(),
                                     it->first.fields.end());
                if (destructorUses(
                        types,
                        *projectedType(
                            types, function.locals[instruction.place.root].type,
                            instruction.place.fields),
                        path)) {
                  join(uses, it->second);
                  join(point.drops, it->second);
                }
                it = memory.erase(it);
              } else
                ++it;
            for (const auto &[path, sources] : rhs) {
              auto key = target.place;
              key.fields.insert(key.fields.end(), path.begin(), path.end());
              join(memory[key], sources);
            }
          }
        } else if (borrowed(instruction.op)) {
          int id = created[b][i][0];
          auto &loan = result.loans[id];
          auto oldTargets = loan.targets.size(),
               oldParents = loan.parents.size();
          loan.mode = instruction.op == ir::Op::BorrowRead ||
                              instruction.op == ir::Op::ViewRead
                          ? ParameterMode::Read
                          : ParameterMode::Mut;
          loan.reserved = instruction.op == ir::Op::ReserveMut;
          loan.targets.insert(targets.begin(), targets.end());
          for (const auto &target : targets)
            join(loan.parents, target.authority);
          if (oldTargets != loan.targets.size() ||
              oldParents != loan.parents.size())
            changed = true;
          value[{}].insert(id);
          point.defines.insert(id);
        } else if (instruction.op == ir::Op::Construct) {
          for (std::size_t field = 0; field < instruction.operands.size();
               ++field)
            for (const auto &[path, sources] :
                 result.values[instruction.operands[field].id]) {
              auto projected = path;
              projected.insert(
                  projected.begin(),
                  Projection::field(static_cast<std::uint32_t>(field)));
              join(value[projected], sources);
            }
        } else if (instruction.op == ir::Op::Project) {
          for (const auto &[path, sources] :
               result.values[instruction.operands[0].id])
            if (!path.empty() &&
                path[0] == Projection::field(
                               static_cast<std::uint32_t>(instruction.number)))
              join(value[ViewPath(path.begin() + 1, path.end())], sources);
        } else if (instruction.op == ir::Op::Phi) {
          for (auto operand : instruction.operands)
            join(value, result.values[operand.id]);
        } else if (instruction.op == ir::Op::Call && !created[b][i].empty()) {
          auto paths = viewPaths(instruction.result.type, types);
          for (std::size_t path = 0; path < paths.size(); ++path) {
            int id = created[b][i][path];
            result.loans[id].mode = types.view(paths[path].second).mode;
            value[paths[path].first].insert(id);
            point.defines.insert(id);
          }
        } else if (instruction.op == ir::Op::ScopeExit) {
          point.dead.clear();
          for (std::size_t local = 0; local < function.locals.size(); ++local) {
            if (function.locals[local].scope != instruction.number ||
                (local < function.parameters &&
                 (function.locals[local].mode == ParameterMode::Read ||
                  function.locals[local].mode == ParameterMode::Mut)))
              continue;
            Place root{static_cast<int>(local), {}};
            drop(root, i, instruction.span, uses);
            point.dead.push_back(root);
            for (auto it = memory.begin(); it != memory.end();) {
              if (prefix(root, it->first)) {
                if (destructorUses(types, function.locals[local].type,
                                   it->first.fields)) {
                  join(uses, it->second);
                  join(point.drops, it->second);
                }
                it = memory.erase(it);
              } else
                ++it;
            }
          }
        }
        if (instruction.op == ir::Op::Call ||
            instruction.op == ir::Op::CatchCall) {
          const auto &callee = program.functions[instruction.callee];
          auto argumentPlace = [&](const Place &relativePlace) {
            auto argument = instruction.operands.at(relativePlace.root);
            auto type = callee.locals[relativePlace.root].type;
            std::set<Target> referents;
            ViewPath path;
            bool located = argument.access != ir::Access::Owned;
            if (located)
              for (auto id : flatten(result.values[argument.id]))
                for (auto target : result.loans.at(id).targets) {
                  target.authority.insert(id);
                  referents.insert(std::move(target));
                }
            for (auto projection : relativePlace.fields) {
              auto priorType = type;
              type = projection.kind == Projection::Kind::Field
                         ? types.product(type).fields.at(projection.index).type
                         : types.view(type).payload;
              if (!located) {
                if (projection.kind == Projection::Kind::Field) {
                  path.push_back(projection);
                  continue;
                }
                for (auto id : result.values[argument.id][path])
                  for (auto target : result.loans.at(id).targets) {
                    target.authority.insert(id);
                    referents.insert(std::move(target));
                  }
                located = true;
              } else if (projection.kind == Projection::Kind::Field) {
                std::set<Target> next;
                for (auto target : referents) {
                  target.place.fields.push_back(projection);
                  next.insert(std::move(target));
                }
                referents = std::move(next);
              } else {
                std::set<Target> next;
                for (const auto &referent : referents) {
                  if (referent.place.root < 0 && memory[referent.place].empty())
                    memory[referent.place].insert(externalLoan(
                        referent.place, priorType,
                        result.externalSources.at(referent.place.root)));
                  for (auto id : memory[referent.place])
                    for (auto target : result.loans.at(id).targets) {
                      target.authority.insert(id);
                      join(target.authority, referent.authority);
                      next.insert(std::move(target));
                    }
                }
                referents = std::move(next);
              }
            }
            return referents;
          };
          auto paths = viewPaths(instruction.result.type, types);
          for (std::size_t path = 0; path < created[b][i].size(); ++path) {
            auto &loan = result.loans.at(created[b][i][path]);
            auto oldTargets = loan.targets.size(),
                 oldParents = loan.parents.size();
            if (auto sources = summaries[instruction.callee].returns.find(
                    paths[path].first);
                sources != summaries[instruction.callee].returns.end())
              for (const auto &source : sources->second) {
                auto referents = argumentPlace(source);
                loan.targets.insert(referents.begin(), referents.end());
              }
            for (auto source : callee.resultSources) {
              auto parents =
                  flatten(result.values[instruction.operands[source].id]);
              std::vector<int> work(parents.begin(), parents.end());
              while (!work.empty()) {
                auto id = work.back();
                work.pop_back();
                for (const auto &target : result.loans.at(id).targets)
                  for (const auto &[location, contents] : memory)
                    if (prefix(target.place, location))
                      for (auto content : contents)
                        if (parents.insert(content).second)
                          work.push_back(content);
              }
              join(loan.parents, parents);
            }
            if (oldTargets != loan.targets.size() ||
                oldParents != loan.parents.size())
              changed = true;
          }
          std::map<Place, std::set<Target>> arguments;
          auto rememberArgument = [&](const Place &place) {
            arguments.try_emplace(place, argumentPlace(place));
          };
          for (const auto &[destination, sources] :
               summaries[instruction.callee].writes) {
            rememberArgument(destination);
            for (const auto &source : sources)
              rememberArgument(source);
          }
          for (const auto &[destination, sources] :
               summaries[instruction.callee].writeDependencies) {
            (void)destination;
            for (const auto &source : sources)
              rememberArgument(source);
          }
          for (const auto &destination :
               summaries[instruction.callee].overwrites)
            rememberArgument(destination);
          if (instruction.op == ir::Op::Call)
            for (const auto &destination :
                 summaries[instruction.callee].overwrites) {
              const auto &destinations = arguments.at(destination);
              if (destinations.size() != 1)
                continue;
              const auto &place = destinations.begin()->place;
              point.overwrites.insert(place);
              for (auto it = memory.begin(); it != memory.end();)
                if (prefix(place, it->first))
                  it = memory.erase(it);
                else
                  ++it;
            }
          for (const auto &[destination, sources] :
               summaries[instruction.callee].writes) {
            int id = effectIds[b][i].at(destination);
            auto &loan = result.loans[id];
            auto oldTargets = loan.targets.size(),
                 oldParents = loan.parents.size();
            auto viewType =
                *projectedType(types, callee.locals[destination.root].type,
                               destination.fields);
            loan.mode = types.view(viewType).mode;
            for (const auto &source : sources)
              for (const auto &referent : arguments.at(source)) {
                loan.targets.insert(referent);
                join(loan.parents, referent.authority);
              }
            if (auto dependencies =
                    summaries[instruction.callee].writeDependencies.find(
                        destination);
                dependencies !=
                summaries[instruction.callee].writeDependencies.end())
              for (const auto &source : dependencies->second)
                for (const auto &referent : arguments.at(source))
                  join(loan.parents, referent.authority);
            const auto &destinations = arguments.at(destination);
            for (const auto &target : destinations)
              memory[target.place].insert(id);
            record(destinations, {{{}, {id}}}, instruction.span);
            point.defines.insert(id);
            if (oldTargets != loan.targets.size() ||
                oldParents != loan.parents.size())
              changed = true;
          }
        }
        // Destructors can use their views on any later unwind edge.
        for (const auto &[location, sources] : memory)
          if (location.root >= 0 &&
              destructorUses(types, function.locals[location.root].type,
                             location.fields))
            join(uses, sources);
        join(point.uses, uses);
        auto previous = result.values[instruction.result.id];
        join(result.values[instruction.result.id], value);
        if (previous != result.values[instruction.result.id])
          changed = true;
        if (result.loans.size() > limits::activeLoans)
          throw std::length_error("view origin limit exceeded");
      }
      if (function.blocks[b].exit.kind == ir::Exit::Return) {
        join(result.returns[b],
             flatten(result.values[function.blocks[b].exit.value.id]));
        for (const auto &[path, sources] :
             result.values[function.blocks[b].exit.value.id])
          for (auto id : sources)
            for (const auto &target : result.loans.at(id).targets)
              if (target.place.root < 0)
                result.effects.returns[path].insert(relative(target.place));
      }
      if (outputs[b] != memory) {
        outputs[b] = std::move(memory);
        changed = true;
      }
    }
  } while (changed);
  for (const auto &place : overwrites(function, result.points))
    if (place.root < 0) {
      auto relative = result.externalPlaces.at(place.root);
      relative.fields.insert(relative.fields.end(), place.fields.begin(),
                             place.fields.end());
      result.effects.overwrites.insert(std::move(relative));
    }
  return result;
}
} // namespace mettle::analysis
