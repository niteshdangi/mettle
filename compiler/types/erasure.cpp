#include "types/type.h"
#include <algorithm>

namespace mettle {
Type TypeStore::erasedType(ErasedType descriptor) {
  std::sort(
      descriptor.associated.begin(), descriptor.associated.end(),
      [](const auto &a, const auto &b) { return a.parameter < b.parameter; });
  syncLookup();
  if (auto existing = findIndexed(
          found(lookup.erased, descriptor.declaration), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Erased)
              return false;
            const auto &prior = erasedTypes[entries[i].index];
            if (prior.declaration != descriptor.declaration ||
                prior.arguments != descriptor.arguments ||
                prior.regionArguments != descriptor.regionArguments ||
                prior.regionParameters != descriptor.regionParameters ||
                prior.regionUniverse != descriptor.regionUniverse ||
                prior.regionRequirements != descriptor.regionRequirements ||
                prior.bound != descriptor.bound ||
                prior.associated.size() != descriptor.associated.size())
              return false;
            for (std::size_t binding = 0; binding < prior.associated.size();
                 ++binding)
              if (prior.associated[binding].parameter !=
                      descriptor.associated[binding].parameter ||
                  prior.associated[binding].argument !=
                      descriptor.associated[binding].argument)
                return false;
            return true;
          }))
    return *existing;
  Type result(builtinTypeCount + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Erased, erasedTypes.size()});
  erasedTypes.push_back(std::move(descriptor));
  return result;
}
Type TypeStore::erasedBound(Type type, RegionId bound) {
  auto descriptor = erased(type);
  if (descriptor.bound == bound)
    return type;
  descriptor.bound = bound;
  return erasedType(std::move(descriptor));
}
void TypeStore::setErasedMethods(Type type, std::vector<CallableType> methods) {
  std::vector<Type> pointers;
  for (const auto &method : methods)
    pointers.push_back(method.result == Type::Unknown ? Type::Unknown
                                                      : callableType(method));
  auto &descriptor =
      erasedTypes.at(entries.at(type.index() - builtinTypeCount).index);
  descriptor.methods = std::move(methods);
  descriptor.methodTypes = std::move(pointers);
}
void TypeStore::setErasedDispatch(Type type, std::vector<Type> owners,
                                  std::vector<std::size_t> slots) {
  auto &descriptor =
      erasedTypes.at(entries.at(type.index() - builtinTypeCount).index);
  descriptor.methodOwners = std::move(owners);
  descriptor.methodSlots = std::move(slots);
}
void TypeStore::setErasedParents(Type type, std::vector<Type> parents) {
  erasedTypes.at(entries.at(type.index() - builtinTypeCount).index)
      .parentInterfaces = std::move(parents);
}
bool TypeStore::isErased(Type type) const {
  return contains(type) && type.index() >= builtinTypeCount &&
         entries[type.index() - builtinTypeCount].kind == EntryKind::Erased;
}
const ErasedType &TypeStore::erased(Type type) const {
  return erasedTypes.at(entries.at(type.index() - builtinTypeCount).index);
}
Type TypeStore::opaqueType(std::string name, Type hidden,
                           std::vector<Type> bounds, bool copyRequested) {
  auto result = declareProduct(std::move(name), copyRequested);
  defineProduct(result, {{"<hidden>", hidden}});
  auto &descriptor =
      products.at(entries.at(result.index() - builtinTypeCount).index);
  descriptor.kind = AggregateKind::Opaque;
  descriptor.opaqueBounds = std::move(bounds);
  return result;
}
bool TypeStore::isOpaque(Type type) const {
  return isProduct(type) && product(type).kind == AggregateKind::Opaque;
}
void TypeStore::setOpaqueBounds(Type type, std::vector<Type> bounds) {
  products.at(entries.at(type.index() - builtinTypeCount).index).opaqueBounds =
      std::move(bounds);
}
} // namespace mettle
