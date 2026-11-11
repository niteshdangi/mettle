#include "types/type.h"
#include <limits>
#include <stdexcept>

namespace mettle {
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
    return declareProduct({}, false);
  case ImportedTypeKind::Parameter:
    return declareParameter({}, false);
  case ImportedTypeKind::View:
  case ImportedTypeKind::Pointer:
    entries.push_back(
        {kind == ImportedTypeKind::View ? EntryKind::View : EntryKind::Pointer,
         views.size()});
    views.push_back({});
    break;
  case ImportedTypeKind::Slice:
    entries.push_back({EntryKind::Slice, slices.size()});
    slices.push_back({});
    break;
  case ImportedTypeKind::Callable:
    entries.push_back({EntryKind::Callable, callables.size()});
    callables.push_back({});
    break;
  case ImportedTypeKind::Erased:
    entries.push_back({EntryKind::Erased, erasedTypes.size()});
    erasedTypes.push_back({});
    break;
  default:
    throw std::invalid_argument("invalid imported type kind");
  }
  return result;
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
    auto descriptor = product(type);
    ImportedProduct result{descriptor, {}, {}};
    if (descriptor.callable >= 0)
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
} // namespace mettle
