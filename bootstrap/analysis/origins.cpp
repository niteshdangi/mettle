#include "analysis/origins.h"
#include "support/limits.h"
#include <algorithm>
#include <deque>
#include <functional>
#include <optional>
#include <set>
#include <stdexcept>

namespace mettle::analysis {
namespace {
using Memory = std::map<Place, Origins>;
std::map<Type, Type> callTypes(const ir::Function &callee,
                               const ir::Instruction &call,
                               const TypeStore &types) {
  std::map<Type, Type> result;
  std::function<void(Type, Type)> pair = [&](Type from, Type to) {
    if (from == to || !result.emplace(from, to).second)
      return;
    if (types.isView(from) && types.isView(to))
      pair(types.view(from).payload, types.view(to).payload);
    if (types.isSlice(from) && types.isSlice(to))
      pair(types.slice(from).element, types.slice(to).element);
    if (types.isProduct(from) && types.isProduct(to)) {
      const auto &a = types.product(from), &b = types.product(to);
      for (std::size_t p = 0;
           p < a.components.size() && p < b.components.size(); ++p)
        pair(a.components[p], b.components[p]);
      for (std::size_t p = 0;
           p < a.genericArguments.size() && p < b.genericArguments.size(); ++p)
        pair(a.genericArguments[p], b.genericArguments[p]);
      if (a.fields.size() == b.fields.size())
        for (std::size_t p = 0; p < a.fields.size(); ++p)
          pair(a.fields[p].type, b.fields[p].type);
    }
    if (types.isErased(from) && types.isErased(to)) {
      const auto &a = types.erased(from), &b = types.erased(to);
      for (std::size_t p = 0; p < a.arguments.size() && p < b.arguments.size();
           ++p)
        pair(a.arguments[p], b.arguments[p]);
    }
  };
  for (std::size_t p = 0;
       p < callee.genericParameters.size() && p < call.typeArguments.size();
       ++p)
    pair(callee.genericParameters[p], call.typeArguments[p]);
  for (std::size_t p = 0; p < callee.parameters && p < call.operands.size();
       ++p)
    pair(callee.locals[p].type, call.operands[p].type);
  if (call.op != ir::Op::CatchCall)
    pair(callee.result, call.result.type);
  return result;
}
bool returnPath(const ViewPath &pattern, const ViewPath &actual) {
  if (pattern.size() != actual.size())
    return false;
  for (std::size_t p = 0; p < pattern.size(); ++p)
    if (pattern[p] != actual[p] &&
        !(pattern[p].kind == Projection::Kind::Opaque &&
          actual[p].kind == Projection::Kind::Field) &&
        !(actual[p].kind == Projection::Kind::Opaque &&
          pattern[p].kind == Projection::Kind::Field))
      return false;
  return true;
}
bool owningHandle(Type type, const TypeStore &types) {
  if (!types.isProduct(type))
    return false;
  auto origin = types.product(type).genericOrigin;
  if (origin == Type::Unknown)
    return false;
  auto spelling = ownerSpelling(types.product(origin).name);
  return !spelling.empty() && spelling != "weak" && spelling != "local weak";
}
std::vector<bool> cyclicBlocks(const ir::Function &function) {
  const auto count = function.blocks.size();
  std::vector<std::vector<std::size_t>> edges(count), reverse(count);
  for (std::size_t block = 0; block < count; ++block) {
    const auto &exit = function.blocks[block].exit;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      edges[block].push_back(exit.first);
    if (exit.kind == ir::Exit::Branch)
      edges[block].push_back(exit.second);
    for (auto next : edges[block])
      reverse[next].push_back(block);
  }
  std::vector<bool> visited(count), cyclic(count);
  std::vector<std::size_t> order;
  for (std::size_t root = 0; root < count; ++root) {
    if (visited[root])
      continue;
    std::vector<std::pair<std::size_t, std::size_t>> stack{{root, 0}};
    visited[root] = true;
    while (!stack.empty()) {
      auto &[block, next] = stack.back();
      if (next == edges[block].size()) {
        order.push_back(block);
        stack.pop_back();
      } else {
        auto successor = edges[block][next++];
        if (!visited[successor]) {
          visited[successor] = true;
          stack.emplace_back(successor, 0);
        }
      }
    }
  }
  visited.assign(count, false);
  for (auto it = order.rbegin(); it != order.rend(); ++it) {
    if (visited[*it])
      continue;
    std::vector<std::size_t> component, work{*it};
    visited[*it] = true;
    while (!work.empty()) {
      auto block = work.back();
      work.pop_back();
      component.push_back(block);
      for (auto prior : reverse[block])
        if (!visited[prior]) {
          visited[prior] = true;
          work.push_back(prior);
        }
    }
    for (auto block : component)
      cyclic[block] = component.size() > 1 ||
                      std::find(edges[block].begin(), edges[block].end(),
                                block) != edges[block].end();
  }
  return cyclic;
}
Origins contents(const Memory &memory, const Place &place) {
  Origins result;
  for (const auto &[location, sources] : memory)
    if (location == place || ((imprecise(place) || imprecise(location)) &&
                              overlaps(place, location)))
      result.insert(sources.begin(), sources.end());
  return result;
}
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
  return containsPlace(parent, child);
}
void append(Place &place, const ViewPath &path) {
  for (auto projection : path)
    project(place, projection);
}
std::vector<std::pair<ViewPath, Type>> viewPaths(Type type,
                                                 const TypeStore &types) {
  std::vector<std::pair<ViewPath, Type>> result;
  std::set<Type> active;
  std::function<void(Type, ViewPath)> visit = [&](Type current, ViewPath path) {
    if (!active.insert(current).second)
      return;
    struct ActiveType {
      std::set<Type> &active;
      Type type;
      ~ActiveType() { active.erase(type); }
    } activeType{active, current};
    if (types.isView(current)) {
      if (result.size() >= limits::activeLoans)
        throw std::length_error("view projection limit exceeded");
      result.emplace_back(std::move(path), current);
      return;
    }
    if (types.isErased(current)) {
      if (result.size() >= limits::activeLoans)
        throw std::length_error("view projection limit exceeded");
      // The hidden contents retain loans even after region erasure.
      result.emplace_back(std::move(path), current);
      return;
    }
    if (types.isSlice(current)) {
      auto element = types.slice(current).element;
      path.push_back(Projection::opaque(element));
      visit(element, std::move(path));
      return;
    }
    if (!types.isProduct(current))
      return;
    const auto &aggregate = types.product(current);
    if (aggregate.kind == AggregateKind::Array &&
        aggregate.arrayCount != Type::Unknown) {
      path.push_back(Projection::opaque(aggregate.components[0]));
      visit(aggregate.components[0], std::move(path));
      return;
    }
    if (aggregate.kind == AggregateKind::Coroutine) {
      path.push_back(Projection::opaque(aggregate.components[1]));
      visit(aggregate.components[1], std::move(path));
      return;
    }
    if (owningHandle(current, types) && !aggregate.genericArguments.empty()) {
      visit(aggregate.genericArguments.front(), path);
      return;
    }
    const auto &fields = types.product(current).fields;
    const auto prior = result.size();
    for (std::size_t i = 0; i < fields.size(); ++i) {
      auto child = path;
      // Payload fields retain their type even inside opaque generic storage.
      child.push_back(
          Projection::element(static_cast<std::uint32_t>(i), fields[i].type));
      visit(fields[i].type, std::move(child));
    }
    if (result.size() == prior && aggregate.genericOrigin != Type::Unknown)
      for (auto argument : aggregate.genericArguments) {
        visit(argument, path);
      }
  };
  visit(type, {});
  return result;
}
ViewPath logicalViewPath(ViewPath path) {
  for (auto &projection : path)
    projection.type = Type::Unknown;
  return path;
}
std::set<ViewPath> contentsOnlyResultPaths(const ir::Function &function,
                                           const TypeStore &types) {
  std::set<ViewPath> result;
  if (!types.isFunctionPointer(function.regionSignature))
    return result;
  std::map<ViewPath, bool> declaredPaths;
  // Regional products may lower to a different shape; their payloads match by
  // erased declaration, static only if every declared occurrence is.
  std::map<std::uint32_t, bool> staticPayloads;
  const auto &signature = types.callable(function.regionSignature);
  auto add = [&](Type declared, std::optional<std::uint32_t> field) {
    for (auto [path, type] : viewPaths(declared, types)) {
      const bool payload =
          types.isErased(type) && types.erased(type).bound == RegionId::Static;
      if (types.isErased(type))
        staticPayloads.try_emplace(types.erased(type).declaration, true)
            .first->second &= payload;
      if (field)
        path.insert(path.begin(), Projection::field(*field));
      declaredPaths.try_emplace(logicalViewPath(std::move(path)), true)
          .first->second &= payload;
    }
  };
  if (signature.error == Type::Unknown)
    add(signature.result, std::nullopt);
  else if (types.isProduct(function.result) &&
           types.product(function.result).kind == AggregateKind::Outcome) {
    add(signature.result, 1);
    add(signature.error, 2);
  }
  for (const auto &[path, type] : viewPaths(function.result, types)) {
    if (auto declared = declaredPaths.find(logicalViewPath(path));
        declared != declaredPaths.end()) {
      if (declared->second)
        result.insert(path);
    } else if (types.isErased(type))
      if (auto found = staticPayloads.find(types.erased(type).declaration);
          found != staticPayloads.end() && found->second)
        result.insert(path);
  }
  return result;
}
std::vector<std::set<ViewPath>>
staticInputContents(const ir::Function &function, const TypeStore &types) {
  if (!types.isFunctionPointer(function.regionSignature))
    return {};
  const auto &signature = types.callable(function.regionSignature);
  if (signature.parameters.size() != function.parameters)
    return {};
  auto uncertain = [&](RegionId region) {
    if (!types.regions().contains(region))
      return true;
    auto kind = types.regions().get(region).kind;
    return kind == RegionKind::Unspecified || kind == RegionKind::Inference ||
           kind == RegionKind::Intersection;
  };
  std::map<RegionId, std::vector<RegionId>> dependents;
  std::set<RegionId> possible{RegionId::Static};
  std::vector<RegionId> pending{RegionId::Static};
  for (const auto &requirement : signature.regionRequirements) {
    dependents[requirement.shorter].push_back(requirement.longer);
    if (uncertain(requirement.shorter) &&
        possible.insert(requirement.shorter).second)
      pending.push_back(requirement.shorter);
  }
  while (!pending.empty()) {
    auto region = pending.back();
    pending.pop_back();
    for (auto longer : dependents[region])
      if (possible.insert(longer).second)
        pending.push_back(longer);
  }
  std::vector<std::set<ViewPath>> result(function.parameters);
  for (std::size_t source = 0; source < function.parameters; ++source)
    for (const auto &[path, type] :
         viewPaths(signature.parameters[source].type, types)) {
      auto region = types.isView(type) ? types.view(type).region
                                       : types.erased(type).bound;
      if (uncertain(region) || possible.contains(region))
        result[source].insert(logicalViewPath(path));
    }
  return result;
}
ViewPath repackPath(const TypeStore &types, Type source, Type target,
                    const ViewPath &path, Type opaque) {
  if (source == target)
    return path;
  if (source == opaque) {
    auto result = repackPath(types, types.product(source).fields[0].type,
                             target, path, opaque);
    result.insert(result.begin(), Projection::field(0));
    return result;
  }
  if (target == opaque) {
    if (path.empty())
      return {};
    return repackPath(types, source, types.product(target).fields[0].type,
                      {path.begin() + 1, path.end()}, opaque);
  }
  if (!path.empty() && types.isProduct(source) && types.isProduct(target)) {
    auto field = path[0];
    auto result =
        repackPath(types, types.product(source).fields[field.index].type,
                   types.product(target).fields[field.index].type,
                   {path.begin() + 1, path.end()}, opaque);
    result.insert(result.begin(), field);
    return result;
  }
  return path;
}
bool borrowed(ir::Op op) {
  return op == ir::Op::ErasedUpcast || op == ir::Op::UnsizeView ||
         op == ir::Op::SliceBorrowRead || op == ir::Op::SliceBorrowMut ||
         op == ir::Op::EraseView || op == ir::Op::BorrowRead ||
         op == ir::Op::BorrowMut || op == ir::Op::ReserveMut ||
         op == ir::Op::ViewRead || op == ir::Op::ViewMut ||
         op == ir::Op::ArrayBorrowRead || op == ir::Op::ArrayBorrowMut;
}
bool interiorStorage(const TypeStore &types, Type type) {
  return types.isProduct(type) &&
         (types.product(type).kind == AggregateKind::Cell ||
          types.product(type).kind == AggregateKind::RefCell);
}
bool cleanupUses(const ProductType &type) {
  return type.hasDestructor || type.nativeCleanup != NativeCleanup::None;
}
bool suppressesCleanup(const TypeStore &types, Type type) {
  return types.isProduct(type) &&
         (types.product(type).kind == AggregateKind::Uninit ||
          types.product(type).kind == AggregateKind::ManualDrop ||
          types.product(type).kind == AggregateKind::Atomic);
}
bool destructorUses(const TypeStore &types, Type type, const ViewPath &path,
                    bool constructed = true) {
  for (auto projection : path) {
    if (suppressesCleanup(types, type))
      return false;
    if (constructed && types.isProduct(type) &&
        cleanupUses(types.product(type)))
      return true;
    if (projection.kind == Projection::Kind::Opaque) {
      type = projection.type;
      constructed = true;
      continue;
    }
    if (projection.kind == Projection::Kind::Field &&
        projection.type != Type::Unknown) {
      type = projection.type;
      constructed = true;
      continue;
    }
    if (!types.isProduct(type))
      return false;
    if (types.product(type).kind == AggregateKind::Array &&
        types.product(type).arrayCount != Type::Unknown)
      type = types.product(type).components[0];
    if (!types.isProduct(type))
      return false;
    if (constructed && cleanupUses(types.product(type)))
      return true;
    type = types.product(type).fields.at(projection.index).type;
    constructed = true;
  }
  return constructed && !suppressesCleanup(types, type) &&
         types.isProduct(type) && cleanupUses(types.product(type));
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
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
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

Origins strongAncestors(const Origins &origins,
                        const std::map<int, Loan> &loans) {
  Origins result = origins;
  std::vector<int> work(origins.begin(), origins.end());
  while (!work.empty()) {
    int id = work.back();
    work.pop_back();
    auto found = loans.find(id);
    if (found == loans.end())
      continue;
    for (auto parent : found->second.parents)
      if (!found->second.borrowed.contains(parent) &&
          result.insert(parent).second)
        work.push_back(parent);
  }
  return result;
}

bool disjointLoans(const Origins &authority, int other,
                   const std::map<int, Loan> &loans) {
  const auto relatives = ancestors({other}, loans);
  for (auto source : authority) {
    for (auto sibling : loans.at(source).disjointReplacements)
      if (relatives.contains(sibling))
        return true;
    if (relatives.contains(source))
      continue;
    const auto parents = ancestors({source}, loans);
    for (auto sibling : loans.at(source).disjointOutputs)
      if (relatives.contains(sibling) && !parents.contains(sibling))
        return true;
  }
  return false;
}

namespace {
// A `Within` bound permits the callee to retain the views contained in the
// source argument in storage reachable from the target argument.
void retainWithin(const ir::Function &function, const TypeStore &types,
                  FunctionEffects &effects) {
  for (auto [source, target] : function.withinFlows) {
    if (source >= function.parameters || target >= function.parameters)
      continue;
    Place destination{static_cast<int>(target), {}};
    auto &inputs = effects.wildWrites[destination];
    for (const auto &[path, type] :
         viewPaths(function.locals[source].type, types)) {
      (void)type;
      Place place{static_cast<int>(source), path};
      place.fields.push_back(Projection::dereference());
      inputs.insert(place);
      effects.retained[destination].insert(std::move(place));
    }
  }
}
} // namespace
OriginInfo origins(const ir::Function &function, const ir::Program &program,
                   const EffectSummaries &summaries) {
  const auto &types = *program.types;
  OriginInfo result;
  const auto contentsOnlyPaths = contentsOnlyResultPaths(function, types);
  const auto staticInputs = contentsOnlyPaths.empty()
                                ? std::vector<std::set<ViewPath>>{}
                                : staticInputContents(function, types);
  std::map<int, std::set<ViewPath>> calleeContents;
  if (function.blocks.empty()) {
    if (function.indirectContract || function.declarationOnly ||
        function.foreignDeclaration) {
      std::set<Place> inputs;
      std::map<int, std::set<Place>> parameterInputs;
      for (std::size_t p = 0; p < function.parameters; ++p) {
        const auto &parameter = function.locals[p];
        auto &sources = parameterInputs[static_cast<int>(p)];
        const auto own = parameter.mode == ParameterMode::Read ||
                         parameter.mode == ParameterMode::Mut;
        if (own)
          sources.insert({static_cast<int>(p), {}});
        for (const auto &[path, type] : viewPaths(parameter.type, types)) {
          (void)type;
          Place source{static_cast<int>(p), path};
          source.fields.push_back(Projection::dereference());
          sources.insert(std::move(source));
        }
        // An access view with no declared region is call-local, so an erased
        // receiver cannot retain it. Declared regions and every contained
        // view may flow.
        auto transient =
            own && std::find(function.callLocalParameters.begin(),
                             function.callLocalParameters.end(),
                             p) != function.callLocalParameters.end();
        if (!transient && own &&
            types.isFunctionPointer(function.regionSignature)) {
          const auto &signature = types.callable(function.regionSignature);
          if (p < signature.parameterRegions.size()) {
            transient =
                types.regions().get(signature.parameterRegions[p]).name ==
                parameter.name;
          }
        }
        // Through a call-local view the erased value's own payload is as
        // transient as the view.
        const auto erasedSelf = types.isErased(parameter.type);
        for (const auto &source : sources)
          if (!transient || (source.fields.size() > (erasedSelf ? 1u : 0u)))
            inputs.insert(source);
      }
      for (std::size_t p = 0; p < function.parameters; ++p)
        if (function.locals[p].mode == ParameterMode::Mut &&
            (types.isErased(function.locals[p].type) ||
             types.isParameter(function.locals[p].type)))
          result.effects.wildWrites[{static_cast<int>(p), {}}] = inputs;
      for (const auto &[path, type] : viewPaths(function.result, types)) {
        for (auto source : function.resultSources) {
          const auto &sources = parameterInputs[static_cast<int>(source)];
          for (auto backing : sources) {
            if (contentsOnlyPaths.contains(path) && backing.fields.empty())
              continue;
            backing.fields.push_back(Projection::opaque(
                types.isView(type) ? types.view(type).payload : Type::Unknown));
            result.effects.returns[path].insert(std::move(backing));
          }
        }
      }
      for (std::size_t p = 0; p < function.parameters; ++p) {
        const auto &parameter = function.locals[p];
        std::set<Type> visiting;
        std::function<void(Type, ViewPath, bool, bool)> writable =
            [&](Type type, ViewPath path, bool write, bool external) {
              if (!visiting.insert(type).second)
                return;
              if (types.isView(type)) {
                if (write && external) {
                  Place destination{static_cast<int>(p), path};
                  // A view of an object that holds the destination cannot be
                  // stored in that destination. A view reached through the
                  // destination can only be its current referent again: a
                  // reborrow through the call-local access view cannot have
                  // the destination's region, so the backing is unchanged.
                  std::set<Place> others;
                  for (const auto &input : inputs)
                    if (!prefix(input, destination) &&
                        !prefix(destination, input))
                      others.insert(input);
                  for (auto backing : others) {
                    backing.fields.push_back(
                        Projection::opaque(types.view(type).payload));
                    result.effects.writes[destination].insert(
                        std::move(backing));
                  }
                  result.effects.writeDependencies[destination] = others;
                }
                const auto &view = types.view(type);
                path.push_back(Projection::dereference());
                writable(view.payload, std::move(path),
                         write && view.mode == ParameterMode::Mut, true);
              } else if (types.isProduct(type)) {
                const auto &fields = types.product(type).fields;
                for (std::size_t i = 0; i < fields.size(); ++i) {
                  auto child = path;
                  child.push_back(
                      Projection::field(static_cast<std::uint32_t>(i)));
                  writable(fields[i].type, std::move(child), write, external);
                }
              }
              visiting.erase(type);
            };
        writable(parameter.type, {}, parameter.mode != ParameterMode::Read,
                 parameter.mode == ParameterMode::Mut);
      }
    }
    retainWithin(function, types, result.effects);
    return result;
  }
  result.points.resize(function.blocks.size());
  result.returns.resize(function.blocks.size());
  result.storedIn.resize(function.blocks.size());
  result.values.resize(function.values);
  // A view stored through a raw pointer is untracked: the destination is
  // unknown, so every exclusive parameter may now retain the views contained
  // in the inputs.
  const auto storesViewsThroughPointer = [&] {
    for (const auto &block : function.blocks)
      for (const auto &instruction : block.instructions)
        if (instruction.op == ir::Op::Machine &&
            (instruction.text.starts_with("ptr.write") ||
             instruction.text == "ptr.replace") &&
            instruction.text != "ptr.write_bytes" &&
            instruction.operands.size() == 2 &&
            !viewPaths(instruction.operands[1].type, types).empty())
          return true;
    return false;
  }();
  if (storesViewsThroughPointer) {
    std::set<Place> contained;
    for (std::size_t p = 0; p < function.parameters; ++p)
      for (const auto &[path, type] :
           viewPaths(function.locals[p].type, types)) {
        (void)type;
        Place source{static_cast<int>(p), path};
        source.fields.push_back(Projection::dereference());
        contained.insert(std::move(source));
      }
    for (std::size_t p = 0; p < function.parameters; ++p)
      if (function.locals[p].mode == ParameterMode::Mut)
        result.effects.wildWrites[{static_cast<int>(p), {}}] = contained;
  }
  const auto cyclic = cyclicBlocks(function);
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
    loan.mode =
        types.isView(type) ? types.view(type).mode : ParameterMode::Read;
    loan.interiorRoot = types.isView(type) &&
                        loan.mode == ParameterMode::Read &&
                        interiorStorage(types, types.view(type).payload);
    loan.parameter = parameter;
    int root = external--;
    result.externalSources[root] = parameter;
    auto relative = key.root >= 0 ? Place{key.root, {}}
                                  : result.externalPlaces.at(key.root);
    append(relative, key.fields);
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
  auto staticSlot = [&](int identity) {
    for (std::size_t p = 0; p < function.locals.size(); ++p)
      if (function.locals[p].storage == StorageDuration::Static &&
          function.locals[p].staticIndex == identity)
        return static_cast<int>(p);
    throw std::length_error("missing resolved static storage root");
  };
  std::function<void(const StaticConstant &, Place)> constantOrigins =
      [&](const StaticConstant &constant, Place destination) {
        if (!types.containsViews(constant.type, true))
          return;
        if (constant.kind == StaticConstant::Kind::Address &&
            types.isView(constant.type)) {
          auto id = synthetic++;
          Loan loan;
          loan.mode = types.view(constant.type).mode;
          Place source{staticSlot(constant.symbol), {}};
          for (auto field : constant.projections)
            source.fields.push_back(Projection::field(field));
          loan.targets.insert({source, {id}});
          result.loans.emplace(id, std::move(loan));
          entry[destination].insert(id);
        }
        if (constant.kind == StaticConstant::Kind::Repeat) {
          auto child = destination;
          child.fields.push_back(
              Projection::opaque(types.product(constant.type).components[0]));
          constantOrigins(constant.fields[0], std::move(child));
          return;
        }
        if (constant.kind != StaticConstant::Kind::Aggregate)
          return;
        auto fields = staticConstantFields(types, constant);
        for (std::size_t i = 0; i < constant.fields.size(); ++i) {
          auto child = destination;
          child.fields.push_back(types.compactArray(constant.type)
                                     ? Projection::opaque(fields->at(i).second)
                                     : Projection::field(fields->at(i).first));
          constantOrigins(constant.fields[i], std::move(child));
        }
      };
  for (std::size_t p = 0; p < function.locals.size(); ++p)
    if (function.locals[p].storage == StorageDuration::Static) {
      const auto &storage = program.statics[function.locals[p].staticIndex];
      if (storage.initializer)
        constantOrigins(*storage.initializer, {static_cast<int>(p), {}});
    }
  std::vector<std::vector<std::vector<int>>> created(function.blocks.size());
  std::vector<std::vector<std::map<Place, int>>> effectIds(
      function.blocks.size());
  std::vector<std::vector<std::map<Place, int>>> wildIds(
      function.blocks.size());
  std::vector<const ir::Instruction *> definitions(function.values, nullptr);
  std::vector<int> storedValues(function.locals.size(), -1);
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    result.points[b].resize(function.blocks[b].instructions.size());
    created[b].resize(function.blocks[b].instructions.size());
    effectIds[b].resize(function.blocks[b].instructions.size());
    wildIds[b].resize(function.blocks[b].instructions.size());
    for (std::size_t i = 0; i < function.blocks[b].instructions.size(); ++i) {
      const auto &instruction = function.blocks[b].instructions[i];
      definitions[instruction.result.id] = &instruction;
      const auto root = instruction.place.root;
      if (types.isSum(function.result) &&
          root >= static_cast<int>(function.parameters) &&
          static_cast<std::size_t>(root) < function.locals.size() &&
          function.locals[root].storage == StorageDuration::Automatic &&
          function.locals[root].type == function.result) {
        auto &stored = storedValues[root];
        if (instruction.place.fields.empty() &&
            instruction.op == ir::Op::Store && stored == -1)
          stored = instruction.operands[0].id;
        else if (!instruction.place.fields.empty() ||
                 (instruction.op != ir::Op::Declare &&
                  instruction.op != ir::Op::Load &&
                  instruction.op != ir::Op::Move))
          stored = -2;
      }
      if (borrowed(instruction.op))
        created[b][i].push_back(instruction.result.id);
      else if (instruction.op == ir::Op::Machine &&
               instruction.text.starts_with("cell.") &&
               types.isView(instruction.result.type))
        created[b][i].push_back(instruction.result.id);
      else if (instruction.op == ir::Op::OpaqueRepack &&
               instruction.result.access != ir::Access::Owned)
        created[b][i].push_back(synthetic++);
      else if (instruction.op == ir::Op::OpaqueRepack ||
               instruction.op == ir::Op::Call ||
               instruction.op == ir::Op::IndirectCall)
        for (const auto &path : viewPaths(instruction.result.type, types)) {
          (void)path;
          created[b][i].push_back(synthetic++);
        }
      if (instruction.op == ir::Op::Call ||
          instruction.op == ir::Op::IndirectCall ||
          instruction.op == ir::Op::CatchCall)
        for (const auto &[destination, sources] :
             summaries[instruction.callee].writes) {
          (void)sources;
          effectIds[b][i].emplace(destination, synthetic++);
        }
    }
  }
  auto returnDefinition = [&](int value) -> const ir::Instruction * {
    std::set<int> visited;
    while (value >= 0 && static_cast<std::size_t>(value) < definitions.size() &&
           visited.insert(value).second) {
      const auto *definition = definitions[value];
      if (!definition || definition->op == ir::Op::VariantConstruct)
        return definition;
      if ((definition->op != ir::Op::Load && definition->op != ir::Op::Move) ||
          !definition->place.fields.empty() || definition->place.root < 0 ||
          static_cast<std::size_t>(definition->place.root) >=
              storedValues.size())
        return nullptr;
      value = storedValues[definition->place.root];
    }
    return nullptr;
  };
  std::vector<std::vector<int>> predecessors(function.blocks.size());
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    const auto &exit = function.blocks[b].exit;
    if (ir::continues(exit.kind) || exit.kind == ir::Exit::Branch)
      predecessors[exit.first].push_back(static_cast<int>(b));
    if (exit.kind == ir::Exit::Branch)
      predecessors[exit.second].push_back(static_cast<int>(b));
  }
  std::vector<Memory> outputs(function.blocks.size());
  std::vector<std::optional<Place>> variantPlaces(function.blocks.size());
  bool changed;
  // Result paths some return leaves without any tracked loan (raw storage).
  std::set<ViewPath> untracked;
  do {
    changed = false;
    untracked.clear();
    for (std::size_t b = 0; b < function.blocks.size(); ++b) {
      Memory memory = b == 0 ? entry : Memory{};
      for (auto predecessor : predecessors[b]) {
        if (!variantPlaces[predecessor]) {
          join(memory, outputs[predecessor]);
          continue;
        }
        const auto &prior = function.blocks[predecessor];
        const auto &test = prior.instructions.back();
        const auto &place = *variantPlaces[predecessor];
        auto type = *projectedType(types, function.locals[test.place.root].type,
                                   test.place.fields);
        const auto &variants = types.product(type).variants;
        std::set<std::uint32_t> fields;
        for (std::size_t variant = 0; variant < variants.size(); ++variant)
          if ((static_cast<std::int64_t>(variant) == test.number) ==
              (static_cast<int>(b) == prior.exit.first))
            fields.insert(variants[variant].fields.begin(),
                          variants[variant].fields.end());
        for (const auto &[location, sources] : outputs[predecessor]) {
          if (prefix(place, location) &&
              location.fields.size() > place.fields.size()) {
            auto field = location.fields[place.fields.size()];
            if (field.kind == Projection::Kind::Field &&
                !fields.contains(field.index))
              continue;
          }
          join(memory[location], sources);
        }
      }
      result.storedIn[b].clear();
      for (const auto &[location, sources] : memory) {
        (void)location;
        join(result.storedIn[b], sources);
      }
      auto resolve = [&](const Place &raw, Origins &uses) {
        std::set<Target> targets{{bases.at(raw.root), {}}};
        auto currentType = function.locals[raw.root].type;
        for (auto projection : raw.fields) {
          if (projection.kind != Projection::Kind::Dereference) {
            currentType = projection.type != Type::Unknown
                              ? projection.type
                              : types.product(currentType)
                                    .fields.at(projection.index)
                                    .type;
            std::set<Target> next;
            for (auto target : targets) {
              project(target.place, projection);
              next.insert(std::move(target));
            }
            targets = std::move(next);
          } else {
            std::set<Target> next;
            for (const auto &target : targets) {
              Origins sources = contents(memory, target.place);
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
                  if (imprecise(target.place))
                    project(
                        referent.place,
                        Projection::opaque(types.isView(currentType)
                                               ? types.view(currentType).payload
                                               : Type::Unknown));
                  referent.authority.insert(id);
                  join(referent.authority, target.authority);
                  next.insert(std::move(referent));
                }
              }
            }
            targets = std::move(next);
            // A raw pointer's pointee has no further view type to follow.
            if (!types.isView(currentType))
              return targets;
            currentType = types.view(currentType).payload;
          }
        }
        return targets;
      };
      // A raw pointer does not carry loans: a view read through one is backed
      // by the object that owns the pointer, so cut the place at the last view.
      auto viewBacking = [&](Place place) {
        auto type = function.locals.at(place.root).type;
        std::size_t kept = 0;
        for (std::size_t i = 0; i < place.fields.size(); ++i) {
          const auto &projection = place.fields[i];
          if (projection.kind == Projection::Kind::Opaque)
            return place;
          if (projection.kind == Projection::Kind::Dereference) {
            if (!types.isView(type)) {
              if (owningHandle(type, types)) {
                type = types.product(type).genericArguments.front();
                kept = i + 1;
                continue;
              }
              place.fields.resize(kept);
              return place;
            }
            type = types.view(type).payload;
            kept = i + 1;
          } else if (projection.type != Type::Unknown)
            type = projection.type;
          else if (types.isProduct(type))
            type = types.product(type).fields.at(projection.index).type;
          else
            return place;
        }
        return place;
      };
      auto relative = [&](const Place &place) {
        auto source = result.externalPlaces.at(place.root);
        append(source, place.fields);
        if (source.fields.size() > limits::typeDepth)
          throw std::length_error("view effect projection limit exceeded");
        return source;
      };
      auto record = [&](const std::set<Target> &targets,
                        const ViewOrigins &value, Span span) {
        for (const auto &target : targets) {
          if (target.place.root >= 0) {
            if (function.locals[target.place.root].storage ==
                StorageDuration::Static)
              for (const auto &[path, sources] : value) {
                (void)path;
                result.escapes.emplace_back(sources, span);
              }
            continue;
          }
          for (const auto &[path, sources] : value) {
            auto destination = relative(target.place);
            append(destination, path);
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
          if (!types.isProduct(type) || suppressesCleanup(types, type))
            return;
          const auto &product = types.product(type);
          if (product.hasDestructor &&
              !(place.root == function.constructorSelfSlot &&
                place.fields.empty())) {
            const auto &effects = summaries.at(product.destructor);
            auto actual = [&](const Place &formal) {
              auto raw = place;
              auto fields = formal.fields;
              if (!product.layout.pinnedFields.empty() && fields.size() >= 2 &&
                  fields[0] == Projection::field(0) &&
                  fields[1] == Projection::dereference())
                fields.erase(fields.begin(), fields.begin() + 2);
              append(raw, fields);
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
        if (instruction.op == ir::Op::IndirectCall)
          join(uses, flatten(result.values[instruction.target.id]));
        if (instruction.op == ir::Op::Call ||
            instruction.op == ir::Op::IndirectCall ||
            instruction.op == ir::Op::CatchCall) {
          std::vector<int> work(uses.begin(), uses.end());
          while (!work.empty()) {
            auto id = work.back();
            work.pop_back();
            for (const auto &target : result.loans.at(id).targets)
              for (const auto &[location, contents] : memory)
                if (prefix(target.place, location) ||
                    (imprecise(target.place) &&
                     overlaps(target.place, location)))
                  for (auto content : contents)
                    if (uses.insert(content).second)
                      work.push_back(content);
          }
        }
        std::set<Target> targets;
        if (instruction.place.root >= 0)
          targets = resolve(instruction.place, uses);
        if (instruction.op == ir::Op::ArrayTake) {
          std::set<Target> elements;
          for (auto target : targets) {
            project(target.place, Projection::opaque(instruction.result.type));
            elements.insert(std::move(target));
          }
          targets = std::move(elements);
        }
        bool indexedBorrow = instruction.op == ir::Op::SliceBorrowRead ||
                             instruction.op == ir::Op::SliceBorrowMut ||
                             instruction.op == ir::Op::ArrayBorrowRead ||
                             instruction.op == ir::Op::ArrayBorrowMut;
        if (indexedBorrow) {
          std::set<Target> elements;
          auto element = types.view(instruction.result.type).payload;
          for (auto target : targets) {
            project(target.place,
                    instruction.number >= 0
                        ? Projection::element(instruction.number, element)
                        : Projection::opaque(element));
            elements.insert(std::move(target));
          }
          targets = std::move(elements);
        }
        point.targets.insert(targets.begin(), targets.end());
        if (instruction.op == ir::Op::Load || instruction.op == ir::Op::Move ||
            instruction.op == ir::Op::ArrayTake) {
          for (const auto &[path, type] :
               viewPaths(instruction.result.type, types)) {
            for (const auto &target : targets) {
              auto key = target.place;
              append(key, path);
              if (key.root < 0 && memory[key].empty())
                memory[key].insert(externalLoan(
                    key, type, result.externalSources.at(key.root)));
              join(value[path], contents(memory, key));
            }
          }
          join(uses, flatten(value));
          if (instruction.op == ir::Op::Move) {
            for (const auto &[path, view] :
                 viewPaths(instruction.result.type, types))
              if (types.isView(view) &&
                  types.view(view).mode == ParameterMode::Mut)
                join(point.movedViews, value[path]);
            for (const auto &target : targets)
              for (auto it = memory.begin(); it != memory.end();)
                if (prefix(target.place, it->first))
                  it = memory.erase(it);
                else
                  ++it;
          }
        } else if (instruction.op == ir::Op::DropPlace) {
          drop(instruction.place, i, instruction.span, uses);
          if (targets.size() == 1 && !imprecise(targets.begin()->place)) {
            for (auto it = memory.begin(); it != memory.end();) {
              if (prefix(targets.begin()->place, it->first))
                it = memory.erase(it);
              else
                ++it;
            }
          }
        } else if (instruction.op == ir::Op::Store ||
                   instruction.op == ir::Op::StorageWrite) {
          if (instruction.op == ir::Op::Store)
            drop(instruction.place, i, instruction.span, uses);
          const auto &rhs = result.values[instruction.operands[0].id];
          record(targets, rhs, instruction.span);
          if (targets.size() == 1 && !imprecise(targets.begin()->place))
            for (const auto &[path, type] :
                 viewPaths(instruction.operands[0].type, types)) {
              (void)type;
              auto key = targets.begin()->place;
              append(key, path);
              point.overwrites.insert(std::move(key));
            }
          for (const auto &target : targets) {
            for (auto it = memory.begin(); it != memory.end();)
              if (prefix(target.place, it->first) && targets.size() == 1 &&
                  !imprecise(target.place)) {
                auto path = ViewPath(it->first.fields.begin() +
                                         target.place.fields.size(),
                                     it->first.fields.end());
                if (instruction.op == ir::Op::Store &&
                    destructorUses(
                        types,
                        *projectedType(
                            types, function.locals[instruction.place.root].type,
                            instruction.place.fields),
                        path,
                        !(instruction.place.root ==
                              function.constructorSelfSlot &&
                          instruction.place.fields.empty()))) {
                  join(uses, it->second);
                  join(point.drops, it->second);
                }
                it = memory.erase(it);
              } else
                ++it;
            for (const auto &[path, sources] : rhs) {
              auto key = target.place;
              append(key, path);
              join(memory[key], sources);
            }
          }
        } else if (instruction.op == ir::Op::Machine &&
                   ((instruction.text.starts_with("cell.") &&
                     instruction.text != "cell.into_inner" &&
                     instruction.text != "cell.as_ptr") ||
                    instruction.text == "mem.replace" ||
                    instruction.text == "mem.swap")) {
          // mem.replace/swap exchange the referents of their exclusive views
          // directly; cells exchange their payload fields.
          const bool direct = instruction.text.starts_with("mem.");
          auto wrapper = instruction.typeArguments[0];
          auto kind =
              direct ? AggregateKind::Product : types.product(wrapper).kind;
          auto operandTargets = [&](std::size_t operand) {
            std::set<Target> referents;
            for (auto id :
                 flatten(result.values[instruction.operands[operand].id]))
              for (auto target : result.loans.at(id).targets) {
                target.authority.insert(id);
                referents.insert(std::move(target));
              }
            return referents;
          };
          auto readValue = [&](const std::set<Target> &referents, Type type) {
            ViewOrigins contentsValue;
            for (const auto &[path, view] : viewPaths(type, types))
              for (const auto &target : referents) {
                auto key = target.place;
                append(key, path);
                if (key.root < 0 && memory[key].empty())
                  memory[key].insert(externalLoan(
                      key, view, result.externalSources.at(key.root)));
                join(contentsValue[path], contents(memory, key));
              }
            return contentsValue;
          };
          bool guard =
              kind == AggregateKind::Ref || kind == AggregateKind::RefMut;
          auto referents = operandTargets(0);
          if (guard) {
            std::set<Target> cells;
            for (auto target : referents) {
              project(target.place, Projection::field(0));
              for (auto id : contents(memory, target.place)) {
                join(uses, {id});
                for (auto cell : result.loans.at(id).targets) {
                  cell.authority.insert(id);
                  cells.insert(std::move(cell));
                }
              }
            }
            if (instruction.text == "cell.clone") {
              for (const auto &cell : cells)
                join(value[{Projection::field(0)}], cell.authority);
            } else {
              int id = created[b][i][0];
              auto &loan = result.loans[id];
              auto oldTargets = loan.targets.size(),
                   oldParents = loan.parents.size();
              loan.mode = types.view(instruction.result.type).mode;
              loan.interiorPayload = true;
              join(loan.parents,
                   flatten(result.values[instruction.operands[0].id]));
              for (auto cell : cells) {
                join(loan.parents, cell.authority);
                project(cell.place, Projection::field(1));
                loan.targets.insert(std::move(cell));
              }
              if (oldTargets != loan.targets.size() ||
                  oldParents != loan.parents.size())
                changed = true;
              value[{}].insert(id);
              point.defines.insert(id);
            }
          } else if (instruction.text == "cell.borrow" ||
                     instruction.text == "cell.borrow_mut" ||
                     instruction.text == "cell.try_borrow" ||
                     instruction.text == "cell.try_borrow_mut") {
            ViewPath path{Projection::field(0)};
            if (instruction.text.starts_with("cell.try_"))
              path.insert(path.begin(), Projection::field(1));
            join(value[path],
                 flatten(result.values[instruction.operands[0].id]));
          } else {
            std::set<Target> payloads;
            for (auto target : referents) {
              if (!direct)
                project(target.place,
                        Projection::field(cellPayloadField(kind)));
              payloads.insert(std::move(target));
            }
            auto payload =
                direct ? wrapper : types.product(wrapper).components[0];
            // Exchange snapshots the old sources before installing the new
            // ones.
            value = readValue(payloads, payload);
            auto install = [&](const std::set<Target> &destinations,
                               const ViewOrigins &rhs) {
              record(destinations, rhs, instruction.span);
              for (const auto &target : destinations) {
                if (destinations.size() == 1 && !imprecise(target.place)) {
                  for (auto it = memory.begin(); it != memory.end();)
                    if (prefix(target.place, it->first))
                      it = memory.erase(it);
                    else
                      ++it;
                }
                for (const auto &[path, sources] : rhs) {
                  auto key = target.place;
                  append(key, path);
                  join(memory[key], sources);
                  if (destinations.size() == 1 && !imprecise(target.place))
                    point.overwrites.insert(key);
                }
              }
            };
            if (instruction.text == "cell.replace" ||
                instruction.text == "mem.replace")
              install(payloads, result.values[instruction.operands[1].id]);
            else if (instruction.text == "cell.swap" ||
                     instruction.text == "mem.swap") {
              std::set<Target> other;
              for (auto target : operandTargets(1)) {
                if (!direct)
                  project(target.place,
                          Projection::field(cellPayloadField(kind)));
                other.insert(std::move(target));
              }
              auto right = readValue(other, payload);
              install(payloads, right);
              install(other, value);
              value.clear();
            }
          }
          join(uses, flatten(value));
        } else if (borrowed(instruction.op)) {
          int id = created[b][i][0];
          auto &loan = result.loans[id];
          auto oldTargets = loan.targets.size(),
               oldParents = loan.parents.size();
          loan.mode = instruction.op == ir::Op::EraseView ||
                              instruction.op == ir::Op::ErasedUpcast ||
                              instruction.op == ir::Op::UnsizeView
                          ? types.view(instruction.result.type).mode
                      : instruction.op == ir::Op::BorrowRead ||
                              instruction.op == ir::Op::ViewRead ||
                              instruction.op == ir::Op::ArrayBorrowRead ||
                              instruction.op == ir::Op::SliceBorrowRead
                          ? ParameterMode::Read
                          : ParameterMode::Mut;
          loan.reserved = instruction.op == ir::Op::ReserveMut;
          loan.interiorRoot =
              loan.mode == ParameterMode::Read &&
              types.isView(instruction.result.type) &&
              interiorStorage(types,
                              types.view(instruction.result.type).payload);
          loan.targets.insert(targets.begin(), targets.end());
          for (const auto &target : targets)
            join(loan.parents, target.authority);
          const auto oldFrozen = loan.frozen.size();
          const bool borrowsPlace = instruction.op == ir::Op::BorrowRead ||
                                    instruction.op == ir::Op::BorrowMut ||
                                    instruction.op == ir::Op::ReserveMut ||
                                    instruction.op == ir::Op::ViewRead ||
                                    instruction.op == ir::Op::ViewMut;
          if (borrowsPlace) {
            std::set<Place> visited;
            std::vector<Target> work(targets.begin(), targets.end());
            while (!work.empty()) {
              auto target = std::move(work.back());
              work.pop_back();
              if (!visited.insert(target.place).second)
                continue;
              for (const auto &[location, stored] : memory)
                if (prefix(target.place, location))
                  for (auto content : stored) {
                    if (content == id ||
                        result.loans.at(content).mode != ParameterMode::Mut)
                      continue;
                    for (auto referent : result.loans.at(content).targets) {
                      referent.authority.insert(content);
                      loan.parents.insert(content);
                      loan.frozen.insert(referent);
                      work.push_back(std::move(referent));
                    }
                  }
              if (visited.size() > limits::activeLoans)
                throw std::length_error("frozen referent limit exceeded");
            }
          }
          if (oldTargets != loan.targets.size() ||
              oldParents != loan.parents.size() ||
              oldFrozen != loan.frozen.size())
            changed = true;
          if (borrowsPlace && loan.mode == ParameterMode::Mut && !loan.reserved)
            for (auto target : loan.frozen) {
              target.authority.insert(id);
              point.targets.insert(std::move(target));
            }
          value[{}].insert(id);
          point.defines.insert(id);
        } else if (instruction.op == ir::Op::Construct ||
                   instruction.op == ir::Op::ArrayRepeat ||
                   instruction.op == ir::Op::VariantConstruct) {
          for (std::size_t field = 0; field < instruction.operands.size();
               ++field)
            for (const auto &[path, sources] :
                 result.values[instruction.operands[field].id]) {
              auto projected = path;
              auto index =
                  instruction.op == ir::Op::VariantConstruct
                      ? types.product(instruction.result.type)
                            .variants[instruction.number]
                            .fields[field]
                  : types.product(instruction.result.type).layout.unionType
                      ? static_cast<std::uint32_t>(instruction.number)
                      : static_cast<std::uint32_t>(field);
              if (instruction.op == ir::Op::ArrayRepeat ||
                  types.compactArray(instruction.result.type))
                projected.insert(
                    projected.begin(),
                    Projection::opaque(
                        types.product(instruction.result.type).components[0]));
              else
                projected.insert(projected.begin(), Projection::field(index));
              join(value[projected], sources);
            }
        } else if (instruction.op == ir::Op::OpaqueRepack) {
          const auto &source = result.values[instruction.operands[0].id];
          auto paths = viewPaths(instruction.result.type, types);
          bool borrowedValue = instruction.result.access != ir::Access::Owned;
          if (borrowedValue)
            paths = {{{}, instruction.result.type}};
          for (std::size_t path = 0; path < paths.size(); ++path) {
            auto sourcePath =
                borrowedValue
                    ? ViewPath{}
                    : repackPath(types, instruction.operands[0].type,
                                 instruction.result.type, paths[path].first,
                                 instruction.opaqueType);
            auto found = source.find(sourcePath);
            if (found == source.end())
              continue;
            auto from = Type::Unknown, to = Type::Unknown;
            if (borrowedValue) {
              from = instruction.operands[0].type;
              to = instruction.result.type;
            } else if (types.isView(paths[path].second)) {
              from = types
                         .view(*projectedType(
                             types, instruction.operands[0].type, sourcePath))
                         .payload;
              to = types.view(paths[path].second).payload;
            }
            auto id = created[b][i][path];
            auto &loan = result.loans[id];
            loan.mode = borrowedValue
                            ? (instruction.result.access == ir::Access::Read
                                   ? ParameterMode::Read
                                   : ParameterMode::Mut)
                        : types.isView(paths[path].second)
                            ? types.view(paths[path].second).mode
                            : ParameterMode::Read;
            if (!borrowedValue && !types.isView(paths[path].second) &&
                std::any_of(found->second.begin(), found->second.end(),
                            [&](int parent) {
                              return result.loans.at(parent).mode ==
                                     ParameterMode::Mut;
                            }))
              loan.mode = ParameterMode::Mut;
            auto oldTargets = loan.targets.size(),
                 oldParents = loan.parents.size();
            join(loan.parents, found->second);
            for (auto parent : found->second)
              for (auto target : result.loans.at(parent).targets) {
                target.authority.insert(parent);
                if (from != to) {
                  if (from == instruction.opaqueType)
                    project(target.place, Projection::field(0));
                  else
                    project(target.place, Projection::opaque(to));
                }
                loan.targets.insert(std::move(target));
              }
            if (oldTargets != loan.targets.size() ||
                oldParents != loan.parents.size())
              changed = true;
            value[paths[path].first].insert(id);
            point.defines.insert(id);
          }
        } else if (instruction.op == ir::Op::Project ||
                   (instruction.op == ir::Op::Machine &&
                    (instruction.text == "storage.assume_init" ||
                     instruction.text == "storage.into_inner" ||
                     instruction.text == "cell.into_inner" ||
                     instruction.text == "pin.into_inner" ||
                     instruction.text == "pin.into_inner_unchecked"))) {
          for (const auto &[path, sources] :
               result.values[instruction.operands[0].id])
            if (!path.empty() &&
                path[0] ==
                    Projection::field(
                        instruction.op == ir::Op::Project
                            ? static_cast<std::uint32_t>(instruction.number)
                        : instruction.text == "cell.into_inner"
                            ? cellPayloadField(
                                  types.product(instruction.operands[0].type)
                                      .kind)
                            : 0))
              join(value[ViewPath(path.begin() + 1, path.end())], sources);
        } else if (instruction.op == ir::Op::Phi) {
          for (auto operand : instruction.operands)
            join(value, result.values[operand.id]);
        } else if (instruction.op == ir::Op::OwnerUnsize) {
          if (!instruction.operands.empty()) {
            const auto &source = result.values[instruction.operands[0].id];
            join(value[{}], flatten(source));
            join(uses, flatten(source));
          }
        } else if ((instruction.op == ir::Op::Call ||
                    instruction.op == ir::Op::IndirectCall) &&
                   !created[b][i].empty()) {
          auto paths = viewPaths(instruction.result.type, types);
          for (std::size_t path = 0; path < paths.size(); ++path) {
            int id = created[b][i][path];
            auto &loan = result.loans[id];
            if (types.isView(paths[path].second))
              loan.mode = types.view(paths[path].second).mode;
            value[paths[path].first].insert(id);
            point.defines.insert(id);
          }
        } else if (instruction.op == ir::Op::ScopeExit) {
          point.dead.clear();
          for (std::size_t local = 0; local < function.locals.size(); ++local) {
            if (function.locals[local].storage == StorageDuration::Static ||
                function.locals[local].scope != instruction.number ||
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
                                   it->first.fields,
                                   static_cast<int>(local) !=
                                       function.constructorSelfSlot)) {
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
            instruction.op == ir::Op::IndirectCall ||
            instruction.op == ir::Op::CatchCall) {
          const auto &callee = program.functions[instruction.callee];
          auto [contentsOnly, inserted] =
              calleeContents.try_emplace(instruction.callee);
          if (inserted)
            contentsOnly->second = contentsOnlyResultPaths(callee, types);
          const auto replacements = callTypes(callee, instruction, types);
          auto rebased = [&](ViewPath path) {
            for (auto &projection : path)
              if (auto found = replacements.find(projection.type);
                  found != replacements.end())
                projection.type = found->second;
            return path;
          };
          std::set<ViewPath> contentsOnlyCallPaths;
          for (const auto &path : contentsOnly->second)
            contentsOnlyCallPaths.insert(rebased(path));
          auto argumentPlace = [&](const Place &relativePlace) {
            auto argument = instruction.operands.at(relativePlace.root);
            auto type = argument.type;
            std::set<Target> referents;
            ViewPath path;
            bool located = argument.access != ir::Access::Owned;
            if (located)
              for (auto id : flatten(result.values[argument.id]))
                for (auto target : result.loans.at(id).targets) {
                  target.authority.insert(id);
                  referents.insert(std::move(target));
                }
            for (auto projection : rebased(relativePlace.fields)) {
              auto priorType = type;
              // A summary path whose projection types did not resolve (an
              // instance over a local opaque type) is retyped structurally;
              // where the structure does not admit the field the type is
              // unknown, which only costs precision.
              bool fieldFits = projection.kind == Projection::Kind::Field &&
                               types.isProduct(type) &&
                               static_cast<std::size_t>(projection.index) <
                                   types.product(type).fields.size();
              type =
                  projection.type != Type::Unknown ? projection.type
                  : projection.kind == Projection::Kind::Field
                      ? (fieldFits
                             ? types.product(type).fields[projection.index].type
                             : Type::Unknown)
                  : projection.kind == Projection::Kind::Slice ? projection.type
                  : projection.kind == Projection::Kind::Opaque ? priorType
                  : types.isView(type)        ? types.view(type).payload
                  : owningHandle(type, types) ? type
                                              : Type::Unknown;
              if (!located) {
                if (projection.kind != Projection::Kind::Dereference) {
                  path.push_back(projection);
                  continue;
                }
                for (auto id : result.values[argument.id][path])
                  for (auto target : result.loans.at(id).targets) {
                    target.authority.insert(id);
                    referents.insert(std::move(target));
                  }
                located = true;
              } else if (projection.kind != Projection::Kind::Dereference) {
                std::set<Target> next;
                for (auto target : referents) {
                  project(target.place, projection);
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
                  for (auto id : contents(memory, referent.place))
                    for (auto target : result.loans.at(id).targets) {
                      if (imprecise(referent.place))
                        project(target.place, Projection::opaque(type));
                      target.authority.insert(id);
                      if (!types.isView(priorType) ||
                          types.view(priorType).mode == ParameterMode::Mut)
                        join(target.authority, referent.authority);
                      next.insert(std::move(target));
                    }
                }
                referents = std::move(next);
              }
            }
            return referents;
          };
          auto holds = [&](int parent, const std::set<Target> &holders) {
            const auto &targets = result.loans.at(parent).targets;
            return !targets.empty() &&
                   std::all_of(targets.begin(), targets.end(),
                               [&](const Target &target) {
                                 return std::any_of(
                                     holders.begin(), holders.end(),
                                     [&](const Target &holder) {
                                       return containsPlace(target.place,
                                                            holder.place);
                                     });
                               });
          };
          auto locationType = [&](const Place &place) -> std::optional<Type> {
            if (place.root >= 0)
              return projectedType(types, function.locals.at(place.root).type,
                                   place.fields);
            auto path = relative(place);
            return projectedType(types, function.locals.at(path.root).type,
                                 path.fields);
          };
          for (const auto &[destination, sources] :
               summaries[instruction.callee].wildWrites) {
            const auto objects = argumentPlace(destination);
            std::map<Place, Type> slots;
            std::set<Place> visited;
            std::vector<Target> work(objects.begin(), objects.end());
            while (!work.empty()) {
              auto object = work.back();
              work.pop_back();
              if (!visited.insert(object.place).second)
                continue;
              if (object.place.root < 0) {
                auto &forwarded =
                    result.effects.wildWrites[relative(object.place)];
                for (const auto &source : sources)
                  for (const auto &input : argumentPlace(source)) {
                    if (input.place.root < 0)
                      forwarded.insert(relative(input.place));
                    else
                      result.escapes.emplace_back(input.authority,
                                                  instruction.span);
                  }
              }
              auto type = locationType(object.place);
              if (!type)
                continue;
              for (const auto &[path, view] : viewPaths(*type, types)) {
                auto slot = object.place;
                append(slot, path);
                slots.emplace(slot, view);
                for (auto id : contents(memory, slot))
                  if (result.loans.at(id).mode == ParameterMode::Mut)
                    for (auto referent : result.loans.at(id).targets)
                      work.push_back(std::move(referent));
              }
              if (visited.size() > limits::activeLoans)
                throw std::length_error(
                    "erased writeback traversal limit exceeded");
            }
            for (const auto &[slot, view] : slots) {
              auto [entry, inserted] =
                  wildIds[b][i].try_emplace(slot, synthetic);
              if (inserted)
                ++synthetic;
              auto id = entry->second;
              auto &loan = result.loans[id];
              auto oldTargets = loan.targets.size(),
                   oldParents = loan.parents.size();
              loan.mode = types.isView(view) ? types.view(view).mode
                                             : ParameterMode::Read;
              auto payload =
                  types.isView(view) ? types.view(view).payload : Type::Unknown;
              for (const auto &source : sources) {
                auto inherit = [&](int parent) {
                  if (parent != id && (source.root != destination.root ||
                                       !holds(parent, objects)))
                    loan.parents.insert(parent);
                };
                bool mutableSource =
                    callee.locals[source.root].mode != ParameterMode::Read;
                std::vector<Target> candidates;
                for (auto input : argumentPlace(source)) {
                  if (source.root != destination.root)
                    for (auto origin : flatten(
                             result
                                 .values[instruction.operands[source.root].id]))
                      input.authority.insert(origin);
                  candidates.push_back(std::move(input));
                }
                // A retained value keeps every loan it carries, whatever the
                // type of the borrowed place.
                const auto &retained = summaries[instruction.callee].retained;
                auto kept = retained.find(destination);
                if (kept != retained.end() && kept->second.contains(source))
                  for (const auto &target : candidates)
                    for (auto parent : target.authority)
                      inherit(parent);
                std::set<std::pair<Place, bool>> seen;
                std::vector<std::pair<Target, bool>> pending;
                for (auto target : candidates)
                  pending.emplace_back(std::move(target), mutableSource);
                while (!pending.empty()) {
                  auto [target, writable] = pending.back();
                  pending.pop_back();
                  if (!seen.emplace(target.place, writable).second)
                    continue;
                  auto type = locationType(target.place);
                  if (!type)
                    continue;
                  if (*type == payload &&
                      (loan.mode == ParameterMode::Read || writable)) {
                    loan.targets.insert(target);
                    for (auto parent : target.authority)
                      inherit(parent);
                  }
                  if (types.isView(*type)) {
                    const auto &reference = types.view(*type);
                    for (auto origin : contents(memory, target.place)) {
                      if (origin == id)
                        continue;
                      for (auto referent : result.loans.at(origin).targets) {
                        referent.authority.insert(origin);
                        if (reference.mode == ParameterMode::Mut)
                          join(referent.authority, target.authority);
                        pending.emplace_back(
                            std::move(referent),
                            writable && reference.mode == ParameterMode::Mut);
                      }
                    }
                  } else if (types.isProduct(*type)) {
                    const auto &fields = types.product(*type).fields;
                    for (std::size_t field = 0; field < fields.size();
                         ++field) {
                      auto child = target;
                      project(
                          child.place,
                          Projection::field(static_cast<std::uint32_t>(field)));
                      pending.emplace_back(std::move(child), writable);
                    }
                  } else if (types.isErased(*type) ||
                             types.isParameter(*type)) {
                    project(target.place, Projection::opaque(payload));
                    loan.targets.insert(target);
                    for (auto parent : target.authority)
                      inherit(parent);
                  }
                  if (seen.size() > limits::activeLoans)
                    throw std::length_error(
                        "erased writeback source limit exceeded");
                }
              }
              memory[slot].insert(id);
              record({Target{slot, {}}}, {{{}, {id}}}, instruction.span);
              point.defines.insert(id);
              if (oldTargets != loan.targets.size() ||
                  oldParents != loan.parents.size())
                changed = true;
            }
          }
          auto paths = viewPaths(instruction.result.type, types);
          for (std::size_t path = 0; path < created[b][i].size(); ++path) {
            auto &loan = result.loans.at(created[b][i][path]);
            auto oldTargets = loan.targets.size(),
                 oldParents = loan.parents.size();
            std::set<int> returnedSources;
            for (const auto &[returnedPath, sources] :
                 summaries[instruction.callee].returns)
              if (returnPath(rebased(returnedPath), paths[path].first))
                for (const auto &source : sources) {
                  returnedSources.insert(source.root);
                  auto referents = argumentPlace(source);
                  loan.targets.insert(referents.begin(), referents.end());
                }
            for (const auto &[returnedPath, sources] :
                 summaries[instruction.callee].staticReturns)
              if (returnPath(rebased(returnedPath), paths[path].first))
                for (auto source : sources) {
                  source.root = staticSlot(source.root);
                  loan.targets.insert({source, {}});
                }
            Origins shadowed, retained;
            for (auto source : callee.resultSources) {
              if (!callee.blocks.empty() &&
                  contentsOnlyCallPaths.contains(paths[path].first) &&
                  !returnedSources.contains(static_cast<int>(source)))
                continue;
              const auto borrow =
                  flatten(result.values[instruction.operands[source].id]);
              auto parents = borrow;
              std::vector<int> work(parents.begin(), parents.end());
              while (!work.empty()) {
                auto id = work.back();
                work.pop_back();
                for (const auto &target : result.loans.at(id).targets)
                  for (const auto &[location, contents] : memory)
                    if (prefix(target.place, location) ||
                        (imprecise(target.place) &&
                         overlaps(target.place, location)))
                      for (auto content : contents)
                        if (parents.insert(content).second)
                          work.push_back(content);
              }
              // A result that names only regions carried inside a borrowed
              // value depends on the shared loans stored there, not on the
              // borrow of the value itself.
              if ((contentsOnlyCallPaths.contains(paths[path].first) ||
                   std::find(callee.resultContents.begin(),
                             callee.resultContents.end(),
                             source) != callee.resultContents.end()) &&
                  callee.locals[source].mode != ParameterMode::Value &&
                  callee.locals[source].mode != ParameterMode::Take) {
                Origins carried;
                std::set_difference(parents.begin(), parents.end(),
                                    borrow.begin(), borrow.end(),
                                    std::inserter(carried, carried.end()));
                if (std::all_of(carried.begin(), carried.end(), [&](auto id) {
                      return result.loans.at(id).mode == ParameterMode::Read;
                    }))
                  parents = std::move(carried);
                else if (!carried.empty()) {
                  // Exclusive contents stay reachable only through the
                  // container borrow while it is live, but the result does not
                  // borrow the container's own storage.
                  join(shadowed, borrow);
                  std::set_difference(parents.begin(), parents.end(),
                                      borrow.begin(), borrow.end(),
                                      std::inserter(retained, retained.end()));
                  join(loan.parents, parents);
                  continue;
                }
              }
              join(retained, parents);
              join(loan.parents, parents);
            }
            Origins borrowed;
            std::set_difference(shadowed.begin(), shadowed.end(),
                                retained.begin(), retained.end(),
                                std::inserter(borrowed, borrowed.end()));
            for (const auto &[returnedPath, destinations] :
                 summaries[instruction.callee].disjointWrites)
              if (returnPath(rebased(returnedPath), paths[path].first))
                for (const auto &destination : destinations) {
                  const auto holders = argumentPlace(destination);
                  for (auto parent = borrowed.begin();
                       parent != borrowed.end();)
                    if (holds(*parent, holders)) {
                      loan.parents.erase(*parent);
                      parent = borrowed.erase(parent);
                    } else {
                      ++parent;
                    }
                  std::set<Target> targets;
                  for (auto target : loan.targets) {
                    std::erase_if(target.authority, [&](auto parent) {
                      return holds(parent, holders);
                    });
                    targets.insert(std::move(target));
                  }
                  loan.targets = std::move(targets);
                }
            const bool borrowedChanged = borrowed != loan.borrowed;
            loan.borrowed = std::move(borrowed);
            if (!types.isView(paths[path].second) &&
                std::any_of(
                    loan.parents.begin(), loan.parents.end(), [&](auto parent) {
                      return result.loans.at(parent).mode == ParameterMode::Mut;
                    }))
              loan.mode = ParameterMode::Mut;
            if (borrowedChanged || oldTargets != loan.targets.size() ||
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
              if (destinations.size() != 1 ||
                  imprecise(destinations.begin()->place))
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
            loan.mode = types.isView(viewType) ? types.view(viewType).mode
                                               : ParameterMode::Read;
            // Views moved within the written argument were reached through
            // loans of the object that holds the destination; those loans
            // govern the access to it, not the stored views.
            const auto &holders = arguments.at(destination);
            auto inherit = [&](const Place &source, const Target &referent) {
              for (auto parent : referent.authority)
                if (source.root != destination.root || !holds(parent, holders))
                  loan.parents.insert(parent);
            };
            for (const auto &source : sources)
              for (const auto &referent : arguments.at(source)) {
                auto stored = referent;
                if (source.root == destination.root)
                  std::erase_if(stored.authority, [&](auto parent) {
                    return holds(parent, holders);
                  });
                loan.targets.insert(std::move(stored));
                inherit(source, referent);
              }
            if (auto dependencies =
                    summaries[instruction.callee].writeDependencies.find(
                        destination);
                dependencies !=
                summaries[instruction.callee].writeDependencies.end())
              for (const auto &source : dependencies->second)
                for (const auto &referent : arguments.at(source))
                  inherit(source, referent);
            const auto &destinations = arguments.at(destination);
            if (destinations.size() == 1 &&
                point.overwrites.contains(destinations.begin()->place))
              point.replacedViews.insert(id);
            for (const auto &target : destinations)
              memory[target.place].insert(id);
            record(destinations, {{{}, {id}}}, instruction.span);
            point.defines.insert(id);
            if (oldTargets != loan.targets.size() ||
                oldParents != loan.parents.size())
              changed = true;
          }
          for (std::size_t path = 0; path < created[b][i].size(); ++path) {
            auto &loan = result.loans.at(created[b][i][path]);
            for (const auto &[destination, written] : effectIds[b][i]) {
              bool separate = false;
              for (const auto &[returnedPath, destinations] :
                   summaries[instruction.callee].disjointWrites)
                separate |=
                    returnPath(rebased(returnedPath), paths[path].first) &&
                    destinations.contains(destination);
              if (separate)
                continue;
              const auto &effect = result.loans.at(written);
              bool aliases = false;
              for (const auto &target : loan.targets)
                for (const auto &stored : effect.targets)
                  aliases |= overlaps(target.place, stored.place);
              if (aliases && loan.parents.insert(written).second)
                changed = true;
            }
          }
        }
        // Destructors can use their views on any later unwind edge.
        for (const auto &[location, sources] : memory)
          if (location.root >= 0 &&
              destructorUses(types, function.locals[location.root].type,
                             location.fields,
                             location.root != function.constructorSelfSlot))
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
        const auto &returned = result.values[function.blocks[b].exit.value.id];
        const auto *definition =
            returnDefinition(function.blocks[b].exit.value.id);
        for (const auto &[path, type] : viewPaths(function.result, types)) {
          (void)type;
          if (definition && definition->op == ir::Op::VariantConstruct &&
              !path.empty() && path.front().kind == Projection::Kind::Field) {
            const auto &fields = types.product(definition->result.type)
                                     .variants[definition->number]
                                     .fields;
            if (std::find(fields.begin(), fields.end(), path.front().index) ==
                fields.end())
              continue;
          }
          auto found = returned.find(path);
          if (found == returned.end() || found->second.empty())
            untracked.insert(path);
        }
        for (const auto &[path, sources] :
             result.values[function.blocks[b].exit.value.id])
          for (auto id : sources)
            for (const auto &target : result.loans.at(id).targets)
              if (target.place.root < 0)
                result.effects.returns[path].insert(
                    viewBacking(relative(target.place)));
              else if (function.locals[target.place.root].storage ==
                       StorageDuration::Static) {
                auto storage = target.place;
                storage.root = function.locals[storage.root].staticIndex;
                result.effects.staticReturns[path].insert(std::move(storage));
              }
      }
      std::optional<Place> variantPlace;
      const auto &block = function.blocks[b];
      if (block.exit.kind == ir::Exit::Branch &&
          block.exit.first != block.exit.second &&
          !block.instructions.empty()) {
        const auto &test = block.instructions.back();
        if (test.op == ir::Op::VariantTest &&
            test.result.id == block.exit.value.id) {
          Origins uses;
          auto targets = resolve(test.place, uses);
          if (targets.size() == 1 && !imprecise(targets.begin()->place))
            variantPlace = targets.begin()->place;
        }
      }
      if (variantPlaces[b] != variantPlace) {
        variantPlaces[b] = std::move(variantPlace);
        changed = true;
      }
      if (outputs[b] != memory) {
        outputs[b] = std::move(memory);
        changed = true;
      }
    }
  } while (changed);
  Origins loopPhis;
  for (std::size_t b = 0; b < function.blocks.size(); ++b)
    if (cyclic[b])
      for (const auto &instruction : function.blocks[b].instructions)
        if (instruction.op == ir::Op::Phi)
          join(loopPhis, flatten(result.values[instruction.result.id]));
  loopPhis = ancestors(loopPhis, result.loans);
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    if (std::none_of(created[b].begin(), created[b].end(),
                     [](const auto &ids) { return !ids.empty(); }))
      continue;
    Origins carried;
    if (cyclic[b]) {
      carried = loopPhis;
      for (auto predecessor : predecessors[b])
        for (const auto &[place, sources] : outputs[predecessor]) {
          (void)place;
          join(carried, sources);
        }
      carried = ancestors(carried, result.loans);
    }
    for (std::size_t i = 0; i < function.blocks[b].instructions.size(); ++i) {
      const auto &instruction = function.blocks[b].instructions[i];
      if ((instruction.op != ir::Op::Call &&
           instruction.op != ir::Op::IndirectCall) ||
          created[b][i].empty())
        continue;
      // One static output identity can represent different loop epochs.
      // Sibling outputs are disjoint only if no output or derived view can
      // reach this call again through storage or a loop Phi.
      if (std::any_of(created[b][i].begin(), created[b][i].end(),
                      [&](int id) { return carried.contains(id); }))
        continue;
      auto paths = viewPaths(instruction.result.type, types);
      for (std::size_t path = 0; path < paths.size(); ++path)
        for (std::size_t other = 0; other < paths.size(); ++other)
          if (other != path &&
              ((types.isView(paths[path].second) &&
                types.view(paths[path].second).mode == ParameterMode::Mut) ||
               (types.isView(paths[other].second) &&
                types.view(paths[other].second).mode == ParameterMode::Mut)))
            result.loans.at(created[b][i][path])
                .disjointOutputs.insert(created[b][i][other]);
      if (instruction.op == ir::Op::Call)
        for (const auto &[returnedPath, destinations] :
             summaries[instruction.callee].disjointWrites)
          for (std::size_t path = 0; path < paths.size(); ++path)
            if (returnPath(returnedPath, paths[path].first))
              for (const auto &destination : destinations)
                if (auto written = effectIds[b][i].find(destination);
                    written != effectIds[b][i].end()) {
                  auto returned = created[b][i][path];
                  result.loans.at(returned).disjointOutputs.insert(
                      written->second);
                  result.loans.at(written->second)
                      .disjointOutputs.insert(returned);
                  if (result.points[b][i].replacedViews.contains(
                          written->second)) {
                    result.loans.at(returned).disjointReplacements.insert(
                        written->second);
                    result.loans.at(written->second)
                        .disjointReplacements.insert(returned);
                  }
                }
    }
  }
  std::map<ViewPath, std::size_t> returning;
  std::map<ViewPath, std::map<Place, std::size_t>> separateWrites;
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    if (function.blocks[b].exit.kind != ir::Exit::Return)
      continue;
    const auto value = function.blocks[b].exit.value;
    const auto *definition = returnDefinition(value.id);
    for (const auto &[path, type] : viewPaths(function.result, types)) {
      (void)type;
      if (definition && definition->op == ir::Op::VariantConstruct &&
          !path.empty() && path.front().kind == Projection::Kind::Field) {
        const auto &fields = types.product(definition->result.type)
                                 .variants[definition->number]
                                 .fields;
        if (std::find(fields.begin(), fields.end(), path.front().index) ==
            fields.end())
          continue;
      }
      ++returning[path];
      auto returned = result.values[value.id].find(path);
      if (returned == result.values[value.id].end() || returned->second.empty())
        continue;
      std::map<Place, bool> separateDestinations;
      for (const auto &[place, written] : outputs[b]) {
        if (place.root >= 0 || written.empty())
          continue;
        auto destination = result.externalPlaces.at(place.root);
        append(destination, place.fields);
        if (!result.effects.writes.contains(destination))
          continue;
        const bool separate = std::all_of(
            returned->second.begin(), returned->second.end(), [&](int source) {
              const auto authority = ancestors({source}, result.loans);
              return std::all_of(
                  written.begin(), written.end(), [&](int other) {
                    return disjointLoans(authority, other, result.loans);
                  });
            });
        separateDestinations.try_emplace(destination, true).first->second &=
            separate;
      }
      for (const auto &[destination, separate] : separateDestinations)
        if (separate)
          ++separateWrites[path][destination];
    }
  }
  for (const auto &[path, destinations] : separateWrites)
    for (const auto &[destination, count] : destinations)
      if (count == returning.at(path))
        result.effects.disjointWrites[path].insert(destination);
  // A result built from raw-pointer storage carries no tracked targets, yet its
  // declared regions promise it stays within the declared inputs: back it with
  // every place those inputs borrow so later access through them conflicts.
  for (const auto &[path, type] : viewPaths(function.result, types)) {
    if ((!untracked.contains(path) &&
         (contentsOnlyPaths.contains(path) ||
          !result.effects.returns[path].empty())) ||
        result.effects.staticReturns.contains(path))
      continue;
    for (auto source : function.resultSources) {
      const auto &parameter = function.locals[source];
      std::set<Place> backing;
      const bool contents = contentsOnlyPaths.contains(path) ||
                            std::find(function.resultContents.begin(),
                                      function.resultContents.end(),
                                      source) != function.resultContents.end();
      if (!contents && (parameter.mode == ParameterMode::Read ||
                        parameter.mode == ParameterMode::Mut))
        backing.insert({static_cast<int>(source), {}});
      for (const auto &[inner, view] : viewPaths(parameter.type, types)) {
        (void)view;
        if (contentsOnlyPaths.contains(path) && source < staticInputs.size() &&
            !staticInputs[source].contains(logicalViewPath(inner)))
          continue;
        Place place{static_cast<int>(source), inner};
        place.fields.push_back(Projection::dereference());
        backing.insert(std::move(place));
      }
      for (auto place : backing) {
        place.fields.push_back(Projection::opaque(
            types.isView(type) ? types.view(type).payload : Type::Unknown));
        result.effects.returns[path].insert(std::move(place));
      }
    }
  }
  for (const auto &place : overwrites(function, result.points))
    if (place.root < 0) {
      auto relative = result.externalPlaces.at(place.root);
      append(relative, place.fields);
      result.effects.overwrites.insert(std::move(relative));
    }
  // A static payload never borrows an input's own storage.
  for (const auto &path : contentsOnlyPaths)
    if (auto found = result.effects.returns.find(path);
        found != result.effects.returns.end())
      std::erase_if(found->second, [](const Place &place) {
        return std::none_of(place.fields.begin(), place.fields.end(),
                            [](const Projection &projection) {
                              return projection.kind ==
                                     Projection::Kind::Dereference;
                            });
      });
  retainWithin(function, types, result.effects);
  return result;
}
} // namespace mettle::analysis
