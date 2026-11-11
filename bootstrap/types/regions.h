#pragma once

#include <compare>
#include <cstdint>
#include <map>
#include <span>
#include <string>
#include <vector>

namespace mettle {
class RegionId {
public:
  constexpr RegionId() = default;
  constexpr std::uint32_t index() const { return value; }
  constexpr bool operator==(const RegionId &) const = default;
  constexpr auto operator<=>(const RegionId &) const = default;
  static const RegionId Unspecified, Static;

private:
  friend class RegionStore;
  explicit constexpr RegionId(std::uint32_t index) : value(index) {}
  std::uint32_t value = 0;
};
inline constexpr RegionId RegionId::Unspecified{0};
inline constexpr RegionId RegionId::Static{1};
enum class RegionKind {
  Unspecified,
  Static,
  Bound,
  Inference,
  Rigid,
  Local,
  Intersection
};
using RegionBinder = std::uint32_t;
using RegionUniverse = std::uint32_t;
struct Region {
  RegionKind kind;
  RegionBinder binder;
  RegionUniverse universe;
  std::string name;
  std::vector<RegionId> sources;
};
struct RegionScope {
  RegionBinder binder;
  RegionUniverse universe;
};
struct RegionBinding {
  RegionId parameter, argument;
};
struct RegionRequirement {
  RegionId longer, shorter;
  bool operator==(const RegionRequirement &) const = default;
  auto operator<=>(const RegionRequirement &) const = default;
};

// Identities, including spelling-independent bound regions, belong to one
// compilation's TypeStore. They are not persistent or cross-store identities.
class RegionStore {
public:
  RegionStore();
  RegionScope binder(RegionUniverse parent = 0, bool higherRanked = false);
  RegionId bound(RegionScope scope, std::string name);
  RegionId rigid(RegionScope scope, std::string name);
  RegionId inference(RegionScope scope);
  RegionId local(RegionScope scope);
  RegionId intersection(std::vector<RegionId> sources);
  const Region &get(RegionId region) const;
  bool contains(RegionId region) const;
  bool visible(RegionId region, RegionUniverse universe) const;
  bool ancestor(RegionUniverse outer, RegionUniverse inner) const;
  RegionUniverse universeParent(RegionUniverse universe) const;
  std::size_t universeCount() const { return parents.size(); }
  RegionId substitute(RegionId region, std::span<const RegionBinding> bindings);

private:
  RegionId add(RegionKind kind, RegionScope scope, std::string name = {});
  std::vector<Region> regions;
  std::map<std::vector<RegionId>, RegionId> intersections;
  std::vector<RegionUniverse> parents{0};
  RegionBinder nextBinder = 1;
};
} // namespace mettle
