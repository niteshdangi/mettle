#pragma once

#include "types/type.h"

namespace mettle {
struct ObjectLayout {
  std::uint64_t size = 0, alignment = 1;
  std::vector<std::uint64_t> fields{};
  bool unaligned = false;
};
std::optional<ObjectLayout> objectLayout(const TypeStore &types, Type type);
std::optional<std::uint64_t> textConstantCount(const TypeStore &types,
                                               const StaticConstant &value);
// True when the layout depends on a coroutine state, which the backend sizes
// from its body's frame; such layouts are unknown before code generation.
bool coroutineDependent(const TypeStore &types, Type type);
bool customRepresentation(const TypeStore &types, Type type);
bool cCompatible(const TypeStore &types, Type type);
bool fieldlessEnumeration(const TypeStore &types, Type type);
} // namespace mettle
