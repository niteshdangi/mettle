#include "types/type.h"
#include <algorithm>
#include <functional>
#include <map>
#include <stdexcept>

namespace mettle {
Type TypeStore::eraseRegions(Type type) {
  if (isPointer(type)) {
    auto descriptor = pointer(type);
    return pointerType(eraseRegions(descriptor.payload), descriptor.mode);
  }
  if (isView(type)) {
    auto descriptor = view(type);
    return viewType(eraseRegions(descriptor.payload), descriptor.mode);
  }
  if (isSlice(type))
    return sliceType(eraseRegions(slice(type).element));
  if (isFunctionPointer(type)) {
    auto descriptor = callable(type);
    for (auto &parameter : descriptor.parameters)
      parameter.type = eraseRegions(parameter.type);
    descriptor.result = eraseRegions(descriptor.result);
    descriptor.error = eraseRegions(descriptor.error);
    descriptor.abiResult = eraseRegions(descriptor.abiResult);
    descriptor.regionParameters.clear();
    descriptor.parameterRegions.clear();
    descriptor.regionRequirements.clear();
    descriptor.regionUniverse = 0;
    return callableType(std::move(descriptor));
  }
  if (isErased(type))
    return erasedBound(type, RegionId::Unspecified);
  if (!isProduct(type))
    return type;
  auto descriptor = product(type);
  if (descriptor.normalizedFields) {
    for (auto &field : descriptor.fields)
      field.type = eraseRegions(field.type);
    auto origin = eraseRegions(descriptor.regionOrigin);
    return regionalProduct(origin, std::move(descriptor.fields), {}, true);
  }
  if (descriptor.regionOrigin != Type::Unknown)
    return eraseRegions(descriptor.regionOrigin);
  if (descriptor.kind == AggregateKind::Opaque)
    return type;
  if (descriptor.genericOrigin != Type::Unknown) {
    for (auto &argument : descriptor.genericArguments)
      argument = eraseRegions(argument);
    return instantiateProduct(descriptor.genericOrigin,
                              std::move(descriptor.genericArguments));
  }
  if (descriptor.kind == AggregateKind::Product ||
      descriptor.kind == AggregateKind::Enumeration ||
      descriptor.kind == AggregateKind::NativeVector ||
      descriptor.kind == AggregateKind::Opaque)
    return type;
  for (auto &component : descriptor.components)
    component = eraseRegions(component);
  if (descriptor.kind == AggregateKind::Array &&
      descriptor.arrayCount != Type::Unknown)
    return arrayType(descriptor.components[0], descriptor.arrayCount);
  return structural(descriptor.kind, std::move(descriptor.components),
                    static_cast<std::uint32_t>(descriptor.fields.size()));
}
Type TypeStore::substituteRegions(Type type,
                                  std::span<const RegionBinding> bindings) {
  std::vector<Type> active;
  using Key = std::pair<Type, std::vector<std::pair<RegionId, RegionId>>>;
  std::map<Key, Type> products;
  std::function<Type(Type, std::span<const RegionBinding>)> visit =
      [&](Type nested, std::span<const RegionBinding> substitutions) -> Type {
    if (substitutions.empty())
      return nested;
    std::vector<std::pair<RegionId, RegionId>> canonical;
    for (const auto &binding : substitutions)
      canonical.emplace_back(binding.parameter, binding.argument);
    std::sort(canonical.begin(), canonical.end());
    Key key{nested, std::move(canonical)};
    if (auto found = products.find(key); found != products.end())
      return found->second;
    if (active.size() >= 128)
      throw std::length_error("region substitution nesting limit exceeded");
    if (std::find(active.begin(), active.end(), nested) != active.end())
      return nested;
    active.push_back(nested);
    auto result = nested;
    if (isProjection(nested)) {
      auto descriptor = parameter(nested);
      std::vector<Type> arguments;
      for (std::size_t i = 2; i < descriptor.operands.size(); ++i)
        arguments.push_back(visit(descriptor.operands[i], substitutions));
      for (auto &region : descriptor.regionArguments)
        region = regionStore.substitute(region, substitutions);
      result = projection(visit(descriptor.operands[0], substitutions),
                          visit(descriptor.operands[1], substitutions),
                          static_cast<std::uint32_t>(descriptor.value),
                          std::move(arguments), descriptor.valueType,
                          descriptor.copyRequested, descriptor.sized,
                          std::move(descriptor.regionArguments));
    } else if (isPointer(nested)) {
      auto record = pointer(nested);
      result = pointerType(visit(record.payload, substitutions), record.mode);
    } else if (isView(nested)) {
      auto record = view(nested);
      result = viewType(visit(record.payload, substitutions), record.mode,
                        regionStore.substitute(record.region, substitutions));
    } else if (isSlice(nested))
      result = sliceType(visit(slice(nested).element, substitutions));
    else if (isProduct(nested)) {
      auto record = product(nested);
      if (record.kind != AggregateKind::Product &&
          record.kind != AggregateKind::Enumeration &&
          record.kind != AggregateKind::NativeVector &&
          record.kind != AggregateKind::Opaque) {
        for (auto &component : record.components)
          component = visit(component, substitutions);
        result =
            record.kind == AggregateKind::Array &&
                    record.arrayCount != Type::Unknown
                ? arrayType(record.components[0], record.arrayCount)
                : structural(record.kind, std::move(record.components),
                             static_cast<std::uint32_t>(record.fields.size()));
      } else {
        if (record.regionPattern != Type::Unknown) {
          for (auto &argument : record.regionArguments)
            argument = regionStore.substitute(argument, substitutions);
          for (auto &argument : record.genericArguments)
            argument = visit(argument, substitutions);
          result = regionalShell(nested, record.regionArguments,
                                 record.genericArguments, record.regionPattern);
          products.emplace(std::move(key), result);
          for (auto &field : record.fields)
            field.type = visit(field.type, substitutions);
          defineProduct(result, std::move(record.fields));
          active.pop_back();
          return result;
        }
        bool changed = false;
        for (auto &field : record.fields) {
          auto substituted = visit(field.type, substitutions);
          changed |= substituted != field.type;
          field.type = substituted;
        }
        for (auto &argument : record.regionArguments) {
          auto substituted = regionStore.substitute(argument, substitutions);
          changed |= substituted != argument;
          argument = substituted;
        }
        if (changed)
          result = regionalProduct(nested, std::move(record.fields),
                                   std::move(record.regionArguments));
      }
    } else if (isFunctionPointer(nested)) {
      auto descriptor = callable(nested);
      std::vector<RegionBinding> visible;
      for (const auto &binding : substitutions)
        if (std::find(descriptor.regionParameters.begin(),
                      descriptor.regionParameters.end(),
                      binding.parameter) == descriptor.regionParameters.end())
          visible.push_back(binding);
      for (auto &parameter : descriptor.parameters)
        parameter.type = visit(parameter.type, visible);
      for (auto &region : descriptor.parameterRegions)
        region = regionStore.substitute(region, visible);
      for (auto &requirement : descriptor.regionRequirements) {
        requirement.longer =
            regionStore.substitute(requirement.longer, visible);
        requirement.shorter =
            regionStore.substitute(requirement.shorter, visible);
      }
      descriptor.result = visit(descriptor.result, visible);
      descriptor.error = visit(descriptor.error, visible);
      descriptor.abiResult = visit(descriptor.abiResult, visible);
      result = callableType(std::move(descriptor));
    } else if (isErased(nested)) {
      auto descriptor = erased(nested);
      std::vector<RegionBinding> visible;
      for (const auto &binding : substitutions)
        if (std::find(descriptor.regionParameters.begin(),
                      descriptor.regionParameters.end(),
                      binding.parameter) == descriptor.regionParameters.end())
          visible.push_back(binding);
      for (auto &argument : descriptor.arguments)
        argument = visit(argument, visible);
      for (auto &binding : descriptor.associated)
        binding.argument = visit(binding.argument, visible);
      for (auto &argument : descriptor.regionArguments)
        argument = regionStore.substitute(argument, visible);
      if (descriptor.bound != RegionId::Unspecified)
        descriptor.bound = regionStore.substitute(descriptor.bound, visible);
      for (auto &requirement : descriptor.regionRequirements) {
        requirement.longer =
            regionStore.substitute(requirement.longer, visible);
        requirement.shorter =
            regionStore.substitute(requirement.shorter, visible);
      }
      if (descriptor.regionParameters.empty()) {
        RegionUniverse universe = 0;
        bool compatible = true;
        for (auto argument : descriptor.regionArguments) {
          auto nestedUniverse = regionStore.get(argument).universe;
          if (regionStore.ancestor(universe, nestedUniverse))
            universe = nestedUniverse;
          else if (!regionStore.ancestor(nestedUniverse, universe))
            compatible = false;
        }
        // Views in arguments and associated bindings also name regions.
        std::function<void(Type)> widen = [&](Type value) {
          if (isView(value)) {
            auto nestedUniverse = regionStore.get(view(value).region).universe;
            if (regionStore.ancestor(universe, nestedUniverse))
              universe = nestedUniverse;
            else if (!regionStore.ancestor(nestedUniverse, universe))
              compatible = false;
            widen(view(value).payload);
          } else if (isProduct(value))
            for (auto component : product(value).components)
              widen(component);
        };
        for (auto argument : descriptor.arguments)
          widen(argument);
        for (const auto &binding : descriptor.associated)
          widen(binding.argument);
        if (compatible)
          descriptor.regionUniverse = universe;
      }
      auto owners = descriptor.methodOwners;
      auto slots = descriptor.methodSlots;
      result = erasedType(std::move(descriptor));
      if (!owners.empty()) {
        for (auto &owner : owners)
          owner = owner == nested ? result : visit(owner, visible);
        setErasedDispatch(result, std::move(owners), std::move(slots));
      }
    }
    active.pop_back();
    return result;
  };
  return visit(type, bindings);
}
} // namespace mettle
