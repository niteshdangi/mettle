#pragma once

#include "types/type.h"
#include <compare>
#include <cstdint>
#include <optional>
#include <span>
#include <tuple>
#include <vector>

namespace mettle {
struct Projection {
  enum class Kind { Field, Dereference, Slice, Opaque };
  Kind kind = Kind::Field;
  std::uint32_t index = 0;
  std::uint32_t count = 0;
  Type type = Type::Unknown;
  static Projection field(std::uint32_t index) { return {Kind::Field, index}; }
  static Projection dereference() { return {Kind::Dereference, 0}; }
  static Projection slice(std::uint32_t first, std::uint32_t count, Type type) {
    return {Kind::Slice, first, count, type};
  }
  // Analysis-only logical referent under a conservative backing place.
  static Projection opaque(Type type) { return {Kind::Opaque, 0, 0, type}; }
  static Projection element(std::uint32_t index, Type type) {
    return {Kind::Field, index, 0, type};
  }
  auto operator<=>(const Projection &other) const {
    auto key = [](const Projection &projection) {
      return std::tuple(projection.kind, projection.index, projection.count,
                        projection.kind == Kind::Field ? Type::Unknown
                                                       : projection.type);
    };
    return key(*this) <=> key(other);
  }
  bool operator==(const Projection &other) const {
    return (*this <=> other) == 0;
  }
};
struct Place {
  int root = -1;
  std::vector<Projection> fields;
  auto operator<=>(const Place &) const = default;
};
std::optional<Type> projectedType(const TypeStore &types, Type root,
                                  std::span<const Projection> fields);
bool overlaps(const Place &first, const Place &second);
bool overlaps(const TypeStore &types, Type root, const Place &first,
              const Place &second);
void project(Place &place, Projection projection);
bool containsPlace(const Place &parent, const Place &child);
bool imprecise(const Place &place);
bool analysisOnly(const Place &place);
bool alignedPlace(const TypeStore &types, Type root,
                  std::span<const Projection> fields);
} // namespace mettle
