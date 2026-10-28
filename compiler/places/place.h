#pragma once

#include "types/type.h"
#include <compare>
#include <cstdint>
#include <optional>
#include <span>
#include <vector>

namespace mettle {
struct Projection {
  enum class Kind { Field, Dereference };
  Kind kind = Kind::Field;
  std::uint32_t index = 0;
  static Projection field(std::uint32_t index) { return {Kind::Field, index}; }
  static Projection dereference() { return {Kind::Dereference, 0}; }
  auto operator<=>(const Projection &) const = default;
};
struct Place {
  int root = -1;
  std::vector<Projection> fields;
  auto operator<=>(const Place &) const = default;
};
std::optional<Type> projectedType(const TypeStore &types, Type root,
                                  std::span<const Projection> fields);
bool overlaps(const Place &first, const Place &second);
} // namespace mettle
