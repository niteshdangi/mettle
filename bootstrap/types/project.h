#pragma once

#include "types/type.h"
#include <map>
#include <memory>

namespace mettle {
class TypeProjection {
public:
  TypeProjection(const TypeStore &source, const TypeStore *prefix = nullptr);
  Type type(Type value);
  RegionId region(RegionId value);
  const std::shared_ptr<TypeStore> &store() const { return destination; }

private:
  const TypeStore &source;
  const TypeStore *prefix;
  std::shared_ptr<TypeStore> destination;
  std::map<Type, Type> types;
  std::map<RegionId, RegionId> regions;
  std::map<RegionUniverse, RegionUniverse> universes;
  std::map<std::pair<RegionBinder, RegionUniverse>, RegionScope> scopes;
  RegionUniverse universe(RegionUniverse value);
  RegionScope scope(RegionScope value);
  void callable(CallableType &value);
  void requirements(std::vector<RegionRequirement> &values);
};
} // namespace mettle
