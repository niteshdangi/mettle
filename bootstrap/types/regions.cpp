#include "types/regions.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace mettle {
RegionStore::RegionStore()
    : regions{{RegionKind::Unspecified, 0, 0, {}, {}},
              {RegionKind::Static, 0, 0, "static", {}}} {}

RegionScope RegionStore::binder(RegionUniverse parent, bool higherRanked) {
  if (parent >= parents.size())
    throw std::out_of_range("invalid parent region universe");
  if (nextBinder == std::numeric_limits<RegionBinder>::max() ||
      parents.size() >= std::numeric_limits<RegionUniverse>::max())
    throw std::length_error("region binder identity limit exceeded");
  auto universe = parent;
  if (higherRanked) {
    universe = static_cast<RegionUniverse>(parents.size());
    parents.push_back(parent);
  }
  return {nextBinder++, universe};
}
RegionId RegionStore::add(RegionKind kind, RegionScope scope,
                          std::string name) {
  if (regions.size() >= std::numeric_limits<std::uint32_t>::max())
    throw std::length_error("region identity limit exceeded");
  RegionId result(static_cast<std::uint32_t>(regions.size()));
  regions.push_back({kind, scope.binder, scope.universe, std::move(name), {}});
  return result;
}
RegionId RegionStore::bound(RegionScope scope, std::string name) {
  return add(RegionKind::Bound, scope, std::move(name));
}
RegionId RegionStore::rigid(RegionScope scope, std::string name) {
  return add(RegionKind::Rigid, scope, std::move(name));
}
RegionId RegionStore::inference(RegionScope scope) {
  return add(RegionKind::Inference, scope);
}
RegionId RegionStore::local(RegionScope scope) {
  return add(RegionKind::Local, scope);
}
RegionId RegionStore::intersection(std::vector<RegionId> sources) {
  std::vector<RegionId> flattened;
  for (auto source : sources) {
    const auto &record = get(source);
    if (record.kind == RegionKind::Intersection)
      flattened.insert(flattened.end(), record.sources.begin(),
                       record.sources.end());
    else if (source != RegionId::Static)
      flattened.push_back(source);
  }
  std::sort(flattened.begin(), flattened.end());
  flattened.erase(std::unique(flattened.begin(), flattened.end()),
                  flattened.end());
  if (flattened.empty())
    return RegionId::Static;
  if (flattened.size() == 1)
    return flattened.front();
  if (auto existing = intersections.find(flattened);
      existing != intersections.end())
    return existing->second;
  auto result = add(RegionKind::Intersection, {0, 0});
  intersections.emplace(flattened, result);
  regions[result.index()].sources = std::move(flattened);
  return result;
}
const Region &RegionStore::get(RegionId region) const {
  return regions.at(region.index());
}
bool RegionStore::contains(RegionId region) const {
  return region.index() < regions.size();
}
bool RegionStore::ancestor(RegionUniverse outer, RegionUniverse inner) const {
  if (outer >= parents.size() || inner >= parents.size())
    return false;
  while (inner != outer && inner != 0)
    inner = parents[inner];
  return outer == inner;
}
RegionUniverse RegionStore::universeParent(RegionUniverse universe) const {
  return parents.at(universe);
}
bool RegionStore::visible(RegionId region, RegionUniverse universe) const {
  const auto &record = get(region);
  if (record.kind == RegionKind::Intersection)
    return std::all_of(record.sources.begin(), record.sources.end(),
                       [&](auto source) { return visible(source, universe); });
  return ancestor(record.universe, universe);
}
RegionId RegionStore::substitute(RegionId region,
                                 std::span<const RegionBinding> bindings) {
  for (const auto &binding : bindings)
    if (binding.parameter == region)
      return binding.argument;
  auto record = get(region);
  if (record.kind != RegionKind::Intersection)
    return region;
  for (auto &source : record.sources)
    source = substitute(source, bindings);
  return intersection(std::move(record.sources));
}
} // namespace mettle
