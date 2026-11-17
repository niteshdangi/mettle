#include "types/project.h"
#include <stdexcept>
#include <type_traits>
#include <utility>

namespace mettle {
TypeProjection::TypeProjection(const TypeStore &source, const TypeStore *prefix)
    : source(source), prefix(prefix),
      destination(prefix ? std::make_shared<TypeStore>(*prefix)
                         : std::make_shared<TypeStore>()) {
  destination->setPointerBits(source.targetPointerBits());
  destination->setVaListAbi(source.vaListAbi());
}

RegionUniverse TypeProjection::universe(RegionUniverse value) {
  if (!value || (prefix && value < prefix->regions().universeCount()))
    return value;
  if (auto found = universes.find(value); found != universes.end())
    return found->second;
  auto parent = universe(source.regions().universeParent(value));
  auto result = destination->regions().binder(parent, true).universe;
  universes.emplace(value, result);
  return result;
}

RegionScope TypeProjection::scope(RegionScope value) {
  if (prefix && value.binder < prefix->regions().nextBinder &&
      value.universe < prefix->regions().universeCount())
    return value;
  auto key = std::pair{value.binder, value.universe};
  if (auto found = scopes.find(key); found != scopes.end())
    return found->second;
  auto result = destination->regions().binder(universe(value.universe));
  scopes.emplace(key, result);
  return result;
}

RegionId TypeProjection::region(RegionId value) {
  if (value == RegionId::Unspecified || value == RegionId::Static ||
      (prefix && prefix->regions().contains(value)))
    return value;
  if (auto found = regions.find(value); found != regions.end())
    return found->second;
  const auto &record = source.regions().get(value);
  RegionId result;
  if (record.kind == RegionKind::Intersection) {
    std::vector<RegionId> sources;
    for (auto item : record.sources)
      sources.push_back(region(item));
    result = destination->regions().intersection(std::move(sources));
  } else {
    auto owner = scope({record.binder, record.universe});
    switch (record.kind) {
    case RegionKind::Bound:
      result = destination->regions().bound(owner, record.name);
      break;
    case RegionKind::Rigid:
      result = destination->regions().rigid(owner, record.name);
      break;
    case RegionKind::Inference:
      result = destination->regions().inference(owner);
      break;
    case RegionKind::Local:
      result = destination->regions().local(owner);
      break;
    default:
      throw std::logic_error("invalid projected region");
    }
  }
  regions.emplace(value, result);
  return result;
}

void TypeProjection::requirements(std::vector<RegionRequirement> &values) {
  for (auto &value : values) {
    value.longer = region(value.longer);
    value.shorter = region(value.shorter);
  }
}

void TypeProjection::callable(CallableType &value) {
  for (auto &parameter : value.parameters)
    parameter.type = type(parameter.type);
  value.result = type(value.result);
  value.error = type(value.error);
  value.abiResult = type(value.abiResult);
  value.environment = type(value.environment);
  for (auto &parameter : value.regionParameters)
    parameter = region(parameter);
  for (auto &parameter : value.parameterRegions)
    parameter = region(parameter);
  value.regionUniverse = universe(value.regionUniverse);
  requirements(value.regionRequirements);
}

Type TypeProjection::type(Type value) {
  if (value.index() < builtinTypeCount || (prefix && prefix->contains(value)))
    return value;
  if (auto found = types.find(value); found != types.end())
    return found->second;
  auto result = destination->declareImportedType(source.importedKind(value));
  types.emplace(value, result);
  auto definition = source.importedDefinition(value);
  auto projectTypes = [&](auto &values) {
    for (auto &item : values)
      item = type(item);
  };
  auto projectRegions = [&](auto &values) {
    for (auto &item : values)
      item = region(item);
  };
  auto bindings = [&](auto &values) {
    for (auto &binding : values) {
      binding.parameter = type(binding.parameter);
      binding.argument = type(binding.argument);
    }
  };
  std::visit(
      [&](auto &record) {
        using T = std::decay_t<decltype(record)>;
        if constexpr (std::is_same_v<T, ImportedProduct>) {
          auto &product = record.descriptor;
          for (auto &field : product.fields)
            field.type = type(field.type);
          projectTypes(product.components);
          projectTypes(product.genericParameters);
          product.genericOrigin = type(product.genericOrigin);
          projectTypes(product.genericArguments);
          product.arrayCount = type(product.arrayCount);
          projectTypes(product.opaqueBounds);
          product.regionOrigin = type(product.regionOrigin);
          projectRegions(product.regionArguments);
          product.regionPattern = type(product.regionPattern);
          product.layout.tag = type(product.layout.tag);
          if (product.vector)
            product.vector->element = type(product.vector->element);
          if (record.closure)
            callable(*record.closure);
          projectTypes(record.coroutineInterior);
        } else if constexpr (std::is_same_v<T, ViewType>) {
          record.payload = type(record.payload);
          record.region = region(record.region);
        } else if constexpr (std::is_same_v<T, ImportedPointer>) {
          record.descriptor.payload = type(record.descriptor.payload);
          record.descriptor.region = region(record.descriptor.region);
        } else if constexpr (std::is_same_v<T, SliceType>) {
          record.element = type(record.element);
        } else if constexpr (std::is_same_v<T, TypeParameter>) {
          record.valueType = type(record.valueType);
          projectTypes(record.operands);
          record.callableConstraint = type(record.callableConstraint);
          projectRegions(record.regionArguments);
          record.erasedCallableConstraint =
              type(record.erasedCallableConstraint);
        } else if constexpr (std::is_same_v<T, CallableType>) {
          callable(record);
        } else if constexpr (std::is_same_v<T, ErasedType>) {
          projectTypes(record.arguments);
          bindings(record.associated);
          for (auto &method : record.methods)
            callable(method);
          projectTypes(record.methodTypes);
          projectTypes(record.methodOwners);
          projectTypes(record.parentInterfaces);
          projectRegions(record.regionArguments);
          projectRegions(record.regionParameters);
          record.regionUniverse = universe(record.regionUniverse);
          requirements(record.regionRequirements);
          record.bound = region(record.bound);
        }
      },
      definition);
  destination->defineImportedType(result, std::move(definition));
  return result;
}
} // namespace mettle
