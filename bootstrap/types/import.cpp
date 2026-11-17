#include "types/type.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace mettle {
Type TypeStore::typeAt(std::size_t index) const {
  if (index >= builtinTypeCount + entries.size())
    throw std::out_of_range("type identity index");
  return Type(static_cast<std::uint32_t>(index));
}

std::shared_ptr<const ProductType> TypeStore::retainProduct(Type type) const {
  if (!isProduct(type))
    throw std::invalid_argument("product snapshot requires a product type");
  return products.retain(entries.at(type.index() - builtinTypeCount).index);
}

std::shared_ptr<const TypeStore::DefinitionSnapshot>
TypeStore::snapshotDefinitions() const {
  auto result = std::make_shared<DefinitionSnapshot>();
  result->entries = entries;
  result->products = products;
  result->views = views;
  result->slices = slices;
  result->callables = callables;
  result->parameters = parameters;
  result->erasedTypes = erasedTypes;
  result->coroutineInteriors = coroutineInteriors;
  return result;
}

bool TypeStore::sharesDefinition(Type type,
                                 const DefinitionSnapshot &other) const {
  if (!contains(type) ||
      type.index() >= builtinTypeCount + other.entries.size())
    return false;
  if (type.index() < builtinTypeCount)
    return true;
  const auto &entry = entries[type.index() - builtinTypeCount];
  const auto &previous = other.entries[type.index() - builtinTypeCount];
  if (entry.kind != previous.kind || entry.index != previous.index)
    return false;
  switch (entry.kind) {
  case EntryKind::Product:
  case EntryKind::Opaque: {
    const auto &value = products[entry.index];
    if (&value != &other.products[previous.index] ||
        (value.callable >= 0 &&
         &callables.at(static_cast<std::size_t>(value.callable)) !=
             &other.callables.at(static_cast<std::size_t>(value.callable))))
      return false;
    const auto interior = coroutineInteriors.find(type.index());
    const auto previousInterior = other.coroutineInteriors.find(type.index());
    return interior == coroutineInteriors.end()
               ? previousInterior == other.coroutineInteriors.end()
               : previousInterior != other.coroutineInteriors.end() &&
                     interior->second == previousInterior->second;
  }
  case EntryKind::View:
  case EntryKind::Pointer:
    return &views[entry.index] == &other.views[previous.index];
  case EntryKind::Slice:
    return &slices[entry.index] == &other.slices[previous.index];
  case EntryKind::Parameter:
    return &parameters[entry.index] == &other.parameters[previous.index];
  case EntryKind::Callable:
    return &callables[entry.index] == &other.callables[previous.index];
  case EntryKind::Erased:
    return &erasedTypes[entry.index] == &other.erasedTypes[previous.index];
  }
  return false;
}

std::vector<Type> TypeStore::referencedTypes(Type type) const {
  std::vector<Type> result;
  auto add = [&](Type value) {
    if (value != Type::Unknown)
      result.push_back(value);
  };
  auto addAll = [&](const auto &values) {
    for (auto value : values)
      add(value);
  };
  auto signature = [&](const CallableType &value) {
    for (const auto &parameter : value.parameters)
      add(parameter.type);
    add(value.result);
    add(value.error);
    add(value.abiResult);
    add(value.environment);
  };
  if (type.index() < builtinTypeCount)
    return result;
  const auto &entry = entries.at(type.index() - builtinTypeCount);
  switch (entry.kind) {
  case EntryKind::Product:
  case EntryKind::Opaque: {
    const auto &value = products[entry.index];
    for (const auto &field : value.fields)
      add(field.type);
    addAll(value.components);
    addAll(value.genericParameters);
    addAll(value.genericArguments);
    add(value.genericOrigin);
    add(value.arrayCount);
    addAll(value.opaqueBounds);
    add(value.regionOrigin);
    add(value.regionPattern);
    add(value.layout.tag);
    if (value.vector)
      add(value.vector->element);
    if (value.callable >= 0)
      signature(callables.at(static_cast<std::size_t>(value.callable)));
    if (auto interior = coroutineInteriors.find(type.index());
        interior != coroutineInteriors.end())
      addAll(interior->second);
    break;
  }
  case EntryKind::View:
  case EntryKind::Pointer:
    add(views[entry.index].payload);
    break;
  case EntryKind::Slice:
    add(slices[entry.index].element);
    break;
  case EntryKind::Parameter: {
    const auto &value = parameters[entry.index];
    add(value.valueType);
    addAll(value.operands);
    add(value.callableConstraint);
    add(value.erasedCallableConstraint);
    break;
  }
  case EntryKind::Callable:
    signature(callables[entry.index]);
    break;
  case EntryKind::Erased: {
    const auto &value = erasedTypes[entry.index];
    addAll(value.arguments);
    for (const auto &binding : value.associated) {
      add(binding.parameter);
      add(binding.argument);
    }
    for (const auto &method : value.methods)
      signature(method);
    addAll(value.methodTypes);
    addAll(value.methodOwners);
    addAll(value.parentInterfaces);
    break;
  }
  }
  std::sort(result.begin(), result.end());
  result.erase(std::unique(result.begin(), result.end()), result.end());
  return result;
}

std::vector<Type> TypeStore::storedTypes() const {
  std::vector<Type> result;
  result.reserve(entries.size());
  for (std::size_t i = 0; i < entries.size(); ++i)
    result.push_back(Type(builtinTypeCount + static_cast<std::uint32_t>(i)));
  return result;
}
Type TypeStore::declareImportedType(ImportedTypeKind kind) {
  if (entries.size() >=
      std::numeric_limits<std::uint32_t>::max() - builtinTypeCount)
    throw std::length_error("type identity limit exceeded");
  Type result(builtinTypeCount + static_cast<std::uint32_t>(entries.size()));
  switch (kind) {
  case ImportedTypeKind::Product:
    entries.push_back({EntryKind::Product, products.size()});
    products.push_uninitialized();
    break;
  case ImportedTypeKind::Parameter:
    entries.push_back({EntryKind::Parameter, parameters.size()});
    parameters.push_uninitialized();
    break;
  case ImportedTypeKind::View:
  case ImportedTypeKind::Pointer:
    entries.push_back(
        {kind == ImportedTypeKind::View ? EntryKind::View : EntryKind::Pointer,
         views.size()});
    views.push_uninitialized();
    break;
  case ImportedTypeKind::Slice:
    entries.push_back({EntryKind::Slice, slices.size()});
    slices.push_uninitialized();
    break;
  case ImportedTypeKind::Callable:
    entries.push_back({EntryKind::Callable, callables.size()});
    callables.push_uninitialized();
    break;
  case ImportedTypeKind::Erased:
    entries.push_back({EntryKind::Erased, erasedTypes.size()});
    erasedTypes.push_uninitialized();
    break;
  default:
    throw std::invalid_argument("invalid imported type kind");
  }
  return result;
}
void TypeStore::deferImportedDefinitions(
    std::span<const Type> ids, std::span<const ImportedTypeIndex> index,
    std::shared_ptr<const ImportedDefinitionLoader> loader,
    std::shared_ptr<const BorrowedDefinitionLoader> borrowed,
    std::shared_ptr<const void> indexOwner) {
  if (!loader || ids.size() != entries.size() || index.size() != ids.size() ||
      lookup.synced || lookup.base || lookup.imported)
    throw std::invalid_argument("deferred definitions require a fresh graph");
  auto imported = indexOwner ? std::make_shared<ImportedLookupData>() : nullptr;
  if (imported)
    imported->owner = std::move(indexOwner);
  auto closureSlots = std::make_shared<std::vector<int>>(ids.size(), -1);
  auto productLoader = std::make_shared<const TypeRecords<ProductType>::Loader>(
      [loader, closureSlots](std::size_t i) {
        auto value = std::get<ImportedProduct>((*loader)(i));
        value.descriptor.callable = closureSlots->at(i);
        return std::move(value.descriptor);
      });
  auto viewLoader = std::make_shared<const TypeRecords<ViewType>::Loader>(
      [loader](std::size_t i) { return std::get<ViewType>((*loader)(i)); });
  auto pointerLoader = std::make_shared<const TypeRecords<ViewType>::Loader>(
      [loader](std::size_t i) {
        return std::move(std::get<ImportedPointer>((*loader)(i)).descriptor);
      });
  auto sliceLoader = std::make_shared<const TypeRecords<SliceType>::Loader>(
      [loader](std::size_t i) { return std::get<SliceType>((*loader)(i)); });
  auto parameterLoader =
      std::make_shared<const TypeRecords<TypeParameter>::Loader>(
          [loader](std::size_t i) {
            return std::get<TypeParameter>((*loader)(i));
          });
  auto callableLoader =
      std::make_shared<const TypeRecords<CallableType>::Loader>(
          [loader](std::size_t i) {
            return std::get<CallableType>((*loader)(i));
          });
  auto closureLoader =
      std::make_shared<const TypeRecords<CallableType>::Loader>(
          [loader](std::size_t i) {
            auto value = std::get<ImportedProduct>((*loader)(i));
            if (!value.closure)
              throw std::logic_error("deferred closure has no signature");
            return std::move(*value.closure);
          });
  auto erasedLoader = std::make_shared<const TypeRecords<ErasedType>::Loader>(
      [loader](std::size_t i) { return std::get<ErasedType>((*loader)(i)); });
  for (std::size_t i = 0; i < ids.size(); ++i) {
    if (ids[i].index() != builtinTypeCount + i)
      throw std::invalid_argument("noncontiguous deferred type identities");
    const auto &entry = entries[i];
    const auto &key = index[i];
    auto ordinal = static_cast<std::uint32_t>(i);
    switch (entry.kind) {
    case EntryKind::Product:
      products.defer(entry.index, i, productLoader);
      if (key.closure) {
        if (callables.size() >
            static_cast<std::size_t>(std::numeric_limits<int>::max()))
          throw std::length_error("closure signature index limit exceeded");
        (*closureSlots)[i] = static_cast<int>(callables.size());
        callables.push_uninitialized();
        callables.defer(callables.size() - 1, i, closureLoader);
      }
      if (!key.coroutineInterior.empty())
        coroutineInteriors[ids[i].index()] = {key.coroutineInterior.begin(),
                                              key.coroutineInterior.end()};
      if (key.genericOrigin != Type::Unknown) {
        if (imported)
          imported->genericInstances.add(key.genericOrigin, ordinal);
        else
          lookup.local.genericInstances[key.genericOrigin].push_back(ordinal);
      }
      if (key.regionOrigin != Type::Unknown) {
        if (imported)
          imported->regionInstances.add(key.regionOrigin, ordinal);
        else
          lookup.local.regionInstances[key.regionOrigin].push_back(ordinal);
      }
      if (imported)
        imported->aggregates.add(key.key, ordinal);
      else
        lookup.local.aggregates[{key.key.begin(), key.key.end()}].push_back(
            ordinal);
      break;
    case EntryKind::View:
      views.defer(entry.index, i, viewLoader);
      if (imported)
        imported->views.add(
            {key.payload, static_cast<int>(key.mode), key.region}, ordinal);
      else
        lookup.local.views.try_emplace(
            std::tuple{key.payload, static_cast<int>(key.mode), key.region},
            ordinal);
      break;
    case EntryKind::Pointer:
      views.defer(entry.index, i, pointerLoader);
      if (imported)
        imported->pointers.add({key.payload, static_cast<int>(key.mode)},
                               ordinal);
      else
        lookup.local.pointers.try_emplace(
            std::pair{key.payload, static_cast<int>(key.mode)}, ordinal);
      break;
    case EntryKind::Slice:
      slices.defer(entry.index, i, sliceLoader);
      if (imported)
        imported->slices.add(key.payload, ordinal);
      else
        lookup.local.slices.try_emplace(key.payload, ordinal);
      break;
    case EntryKind::Parameter:
      parameters.defer(entry.index, i, parameterLoader);
      if (key.parameterKind == TypeParameterKind::Value) {
        if (imported)
          imported->constants.add({key.valueType, key.magnitude}, ordinal);
        else
          lookup.local.constants[{key.valueType, key.magnitude}].push_back(
              ordinal);
      } else if (imported)
        imported->operands.add(key.key, ordinal);
      else
        lookup.local.operands[{key.key.begin(), key.key.end()}].push_back(
            ordinal);
      break;
    case EntryKind::Callable:
      callables.defer(entry.index, i, callableLoader);
      if (imported)
        imported->callables.add({key.regionUniverse,
                                 key.callableRegionParameters,
                                 key.callableParameterRegions,
                                 key.callableRegionRequirements, key.key},
                                ordinal);
      else
        lookup.local
            .callables[{key.regionUniverse,
                        {key.callableRegionParameters.begin(),
                         key.callableRegionParameters.end()},
                        {key.callableParameterRegions.begin(),
                         key.callableParameterRegions.end()},
                        {key.callableRegionRequirements.begin(),
                         key.callableRegionRequirements.end()},
                        {key.key.begin(), key.key.end()}}]
            .push_back(ordinal);
      break;
    case EntryKind::Erased:
      erasedTypes.defer(entry.index, i, erasedLoader);
      if (imported)
        imported->erased.add(key.declaration, ordinal);
      else
        lookup.local.erased[key.declaration].push_back(ordinal);
      break;
    case EntryKind::Opaque:
      throw std::logic_error("opaque entry in an imported type graph");
    }
  }
  if (imported) {
    imported->genericInstances.seal();
    imported->regionInstances.seal();
    imported->aggregates.seal();
    imported->views.seal();
    imported->pointers.seal();
    imported->slices.seal();
    imported->erased.seal();
    imported->operands.seal();
    imported->callables.seal();
    imported->constants.seal();
    lookup.imported = std::move(imported);
  }
  lookup.synced = entries.size();
  borrowedDefinitions = std::move(borrowed);
  borrowedDefinitionCount = ids.size();
}
std::optional<BorrowedTypeDefinition>
TypeStore::borrowedDefinition(Type type) const {
  if (!borrowedDefinitions || type.index() < builtinTypeCount ||
      type.index() - builtinTypeCount >= borrowedDefinitionCount)
    return std::nullopt;
  auto ordinal = type.index() - builtinTypeCount;
  const auto &entry = entries.at(ordinal);
  bool materialized = false;
  switch (entry.kind) {
  case EntryKind::Product:
  case EntryKind::Opaque:
    materialized = products.isMaterialized(entry.index);
    break;
  case EntryKind::View:
  case EntryKind::Pointer:
    materialized = views.isMaterialized(entry.index);
    break;
  case EntryKind::Slice:
    materialized = slices.isMaterialized(entry.index);
    break;
  case EntryKind::Parameter:
    materialized = parameters.isMaterialized(entry.index);
    break;
  case EntryKind::Callable:
    materialized = callables.isMaterialized(entry.index);
    break;
  case EntryKind::Erased:
    materialized = erasedTypes.isMaterialized(entry.index);
    break;
  }
  if (materialized)
    return std::nullopt;
  return (*borrowedDefinitions)(ordinal);
}
std::optional<RegionId> TypeStore::unitViewRegion(Type type) const {
  if (!isView(type))
    return std::nullopt;
  return inspectView(type, [](const auto &record) -> std::optional<RegionId> {
    return record.payload == Type::Unit ? std::optional(record.region)
                                        : std::nullopt;
  });
}
std::uint32_t TypeStore::erasedDeclaration(Type type) const {
  return inspectErased(type,
                       [](const auto &record) { return record.declaration; });
}
ImportedTypeKind TypeStore::importedKind(Type type) const {
  if (type.index() < builtinTypeCount || !contains(type))
    throw std::invalid_argument("imported definition requires a stored type");
  switch (entries[type.index() - builtinTypeCount].kind) {
  case EntryKind::Product:
    return ImportedTypeKind::Product;
  case EntryKind::View:
    return ImportedTypeKind::View;
  case EntryKind::Pointer:
    return ImportedTypeKind::Pointer;
  case EntryKind::Slice:
    return ImportedTypeKind::Slice;
  case EntryKind::Parameter:
    return ImportedTypeKind::Parameter;
  case EntryKind::Callable:
    return ImportedTypeKind::Callable;
  case EntryKind::Erased:
    return ImportedTypeKind::Erased;
  case EntryKind::Opaque:
    break;
  }
  throw std::logic_error("unrepresented semantic type kind");
}
ImportedTypeDefinition TypeStore::importedDefinition(Type type) const {
  switch (importedKind(type)) {
  case ImportedTypeKind::Product: {
    ImportedProduct result{product(type), {}, {}};
    if (result.descriptor.callable >= 0)
      result.closure = callable(type);
    result.descriptor.callable = -1;
    if (auto held = coroutineInteriors.find(type.index());
        held != coroutineInteriors.end())
      result.coroutineInterior = held->second;
    return result;
  }
  case ImportedTypeKind::View:
    return view(type);
  case ImportedTypeKind::Pointer:
    return ImportedPointer{pointer(type)};
  case ImportedTypeKind::Slice:
    return slice(type);
  case ImportedTypeKind::Parameter:
    return parameter(type);
  case ImportedTypeKind::Callable:
    return callable(type);
  case ImportedTypeKind::Erased:
    return erased(type);
  }
  throw std::logic_error("unrepresented semantic type kind");
}
ImportedTypeDefinitionView TypeStore::importedDefinitionView(Type type) const {
  switch (importedKind(type)) {
  case ImportedTypeKind::Product: {
    const auto &descriptor = product(type);
    auto interior = coroutineInteriors.find(type.index());
    return ImportedProductView{
        descriptor, descriptor.callable >= 0 ? &callable(type) : nullptr,
        interior != coroutineInteriors.end()
            ? std::span<const Type>(interior->second)
            : std::span<const Type>{}};
  }
  case ImportedTypeKind::View:
    return &view(type);
  case ImportedTypeKind::Pointer:
    return ImportedPointerView{pointer(type)};
  case ImportedTypeKind::Slice:
    return &slice(type);
  case ImportedTypeKind::Parameter:
    return &parameter(type);
  case ImportedTypeKind::Callable:
    return &callable(type);
  case ImportedTypeKind::Erased:
    return &erased(type);
  }
  throw std::logic_error("unrepresented semantic type kind");
}
void TypeStore::defineImportedType(Type type,
                                   ImportedTypeDefinition definition) {
  if (static_cast<std::size_t>(importedKind(type)) != definition.index())
    throw std::invalid_argument("imported type definition kind mismatch");
  auto entry = entries[type.index() - builtinTypeCount];
  bool changedKey = false;
  if (type.index() - builtinTypeCount < lookup.synced)
    std::visit(
        [&](const auto &record) {
          using T = std::decay_t<decltype(record)>;
          if constexpr (std::is_same_v<T, ImportedProduct>) {
            const auto &prior = products[entry.index];
            changedKey =
                prior.genericOrigin != record.descriptor.genericOrigin ||
                prior.regionOrigin != record.descriptor.regionOrigin ||
                prior.components != record.descriptor.components;
          } else if constexpr (std::is_same_v<T, ImportedPointer>) {
            const auto &prior = views[entry.index];
            changedKey = prior.payload != record.descriptor.payload ||
                         prior.mode != record.descriptor.mode;
          } else if constexpr (std::is_same_v<T, ViewType>) {
            const auto &prior = views[entry.index];
            changedKey = prior.payload != record.payload ||
                         prior.mode != record.mode ||
                         prior.region != record.region;
          } else if constexpr (std::is_same_v<T, SliceType>)
            changedKey = slices[entry.index].element != record.element;
          else if constexpr (std::is_same_v<T, TypeParameter>) {
            const auto &prior = parameters[entry.index];
            changedKey = prior.kind != record.kind ||
                         prior.valueType != record.valueType ||
                         prior.numeric.magnitude != record.numeric.magnitude ||
                         prior.operands != record.operands;
          } else if constexpr (std::is_same_v<T, CallableType>)
            changedKey =
                callableKey(callables[entry.index]) != callableKey(record);
          else
            changedKey =
                erasedTypes[entry.index].declaration != record.declaration;
        },
        definition);
  std::visit(
      [&](auto &&record) {
        using T = std::decay_t<decltype(record)>;
        if constexpr (std::is_same_v<T, ImportedProduct>) {
          if (record.descriptor.callable != -1)
            throw std::invalid_argument(
                "imported callable index is not semantic");
          if (record.closure) {
            auto prior = products[entry.index].callable;
            if (prior >= 0) {
              record.descriptor.callable = prior;
              callables[static_cast<std::size_t>(prior)] =
                  std::move(*record.closure);
            } else {
              record.descriptor.callable = static_cast<int>(callables.size());
              callables.push_back(std::move(*record.closure));
            }
          }
          products[entry.index] = std::move(record.descriptor);
          if (!record.coroutineInterior.empty())
            coroutineInteriors[type.index()] =
                std::move(record.coroutineInterior);
          else
            coroutineInteriors.erase(type.index());
        } else if constexpr (std::is_same_v<T, ImportedPointer>)
          views[entry.index] = std::move(record.descriptor);
        else if constexpr (std::is_same_v<T, ViewType>)
          views[entry.index] = std::move(record);
        else if constexpr (std::is_same_v<T, SliceType>)
          slices[entry.index] = std::move(record);
        else if constexpr (std::is_same_v<T, TypeParameter>)
          parameters[entry.index] = std::move(record);
        else if constexpr (std::is_same_v<T, CallableType>)
          callables[entry.index] = std::move(record);
        else
          erasedTypes[entry.index] = std::move(record);
      },
      std::move(definition));
  if (changedKey)
    lookup = {};
}

void TypeStore::remapImportedSymbols(std::span<const Type> types,
                                     const ImportedSymbolRemap &symbols) {
  auto remap = [](std::uint32_t index, std::span<const std::uint32_t> values) {
    if (index >= values.size())
      throw std::invalid_argument("missing imported symbol remap");
    return values[index];
  };
  auto function = [&](int &index, std::span<const std::uint32_t> values) {
    if (index < 0)
      return;
    const auto mapped = remap(static_cast<std::uint32_t>(index), values);
    if (mapped > static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
      throw std::invalid_argument("imported function is not representable");
    index = static_cast<int>(mapped);
  };
  bool indexed = false;
  for (auto type : types) {
    const auto offset = type.index() - builtinTypeCount;
    const auto &entry = entries.at(offset);
    indexed |= offset < lookup.synced;
    switch (entry.kind) {
    case EntryKind::Product:
    case EntryKind::Opaque: {
      auto &record = products.at(entry.index);
      function(record.destructor, symbols.functions);
      if (record.package != unknownPackage)
        record.package = remap(record.package, symbols.packages);
      if (record.callable >= 0)
        function(
            callables.at(static_cast<std::size_t>(record.callable)).function,
            symbols.closures);
      break;
    }
    case EntryKind::Callable:
      function(callables.at(entry.index).function, symbols.closures);
      break;
    case EntryKind::Erased: {
      auto &record = erasedTypes.at(entry.index);
      record.declaration = remap(record.declaration, symbols.interfaces);
      for (auto &method : record.methods)
        function(method.function, symbols.closures);
      break;
    }
    default:
      break;
    }
  }
  if (indexed)
    lookup = {};
}
} // namespace mettle
