#include "cleanup/plan.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>
#include <stdexcept>

namespace mettle::cleanup {
Plan plan(const ir::Function &function, const TypeStore &types) {
  Plan result;
  result.scopes.resize(function.scopes.size());
  std::function<int(const Place &, Type, bool)> add = [&](const Place &place,
                                                          Type type,
                                                          bool indirect) {
    if (auto found = result.indices.find(place); found != result.indices.end())
      return found->second;
    if (result.places.size() >= limits::cleanupPlaces)
      throw std::length_error("cleanup place limit exceeded");
    int id = static_cast<int>(result.places.size());
    result.indices.emplace(place, id);
    result.places.push_back(
        {place,
         type,
         types.isProduct(type) ? types.product(type).destructor : -1,
         {},
         indirect,
         types.isProduct(type) ? types.product(type).nativeCleanup
                               : NativeCleanup::None});
    if (types.isProduct(type) &&
        types.product(type).kind == AggregateKind::VarArgs)
      result.places[id].nativeAction = NativeCleanup::VaListEnd;
    if (types.isProduct(type) &&
        types.product(type).kind != AggregateKind::VarArgs &&
        types.product(type).kind != AggregateKind::Uninit &&
        types.product(type).kind != AggregateKind::ManualDrop) {
      const auto &fields = types.product(type).fields;
      for (std::size_t i = 0; i < fields.size(); ++i) {
        auto child = place;
        child.fields.push_back(
            Projection::field(static_cast<std::uint32_t>(i)));
        int field = add(child, fields[i].type, indirect);
        result.places[id].fields.push_back(field);
      }
    }
    return id;
  };
  std::vector<std::size_t> order(function.locals.size());
  for (std::size_t i = 0; i < order.size(); ++i)
    order[i] = i;
  std::stable_sort(order.begin(), order.end(), [&](auto a, auto b) {
    return function.locals[a].order > function.locals[b].order;
  });
  for (auto index : order) {
    const auto &local = function.locals[index];
    if (!types.needsDrop(local.type))
      continue;
    bool borrowed =
        local.storage == StorageDuration::Static ||
        (index < function.parameters && (local.mode == ParameterMode::Read ||
                                         local.mode == ParameterMode::Mut));
    int id = add({static_cast<int>(index), {}}, local.type, borrowed);
    if (static_cast<int>(index) == function.constructorSelfSlot)
      result.places[id].destructor = -1;
    if (!borrowed) {
      result.unwind.push_back(id);
      if (local.scope >= 0)
        result.scopes.at(local.scope).push_back(id);
    }
  }
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions) {
      if (instruction.op == ir::Op::DropPlace) {
        auto type = projectedType(
                        types, function.locals.at(instruction.place.root).type,
                        instruction.place.fields)
                        .value();
        if (types.needsDrop(type)) {
          auto root = add(instruction.place, type, true);
          if (std::find(result.unwind.begin(), result.unwind.end(), root) ==
              result.unwind.end())
            result.unwind.push_back(root);
        }
        continue;
      }
      if (instruction.op != ir::Op::Store)
        continue;
      bool indirect =
          std::any_of(instruction.place.fields.begin(),
                      instruction.place.fields.end(), [](auto projection) {
                        return projection.kind == Projection::Kind::Dereference;
                      });
      if (!indirect)
        continue;
      auto type =
          projectedType(types, function.locals.at(instruction.place.root).type,
                        instruction.place.fields)
              .value();
      if (types.needsDrop(type))
        add(instruction.place, type, true);
    }
  return result;
}
} // namespace mettle::cleanup
