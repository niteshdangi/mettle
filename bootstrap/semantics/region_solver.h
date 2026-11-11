#pragma once

#include "types/type.h"
#include <cstddef>
#include <map>
#include <optional>
#include <tuple>
#include <utility>
#include <vector>

namespace mettle {
enum class RegionAnswer { Proven, Rejected, Inconclusive };
using RegionOutlives = RegionRequirement;
struct RegionEnvironment {
  RegionUniverse universe = 0;
  std::vector<RegionOutlives> assumptions;
  std::vector<std::pair<RegionId, RegionId>> substitutions;
};
class RegionSolver {
public:
  explicit RegionSolver(const RegionStore &regions) : regions(regions) {}
  RegionAnswer outlives(RegionId longer, RegionId shorter,
                        const RegionEnvironment &environment);
  RegionAnswer leakCheck(const RegionEnvironment &environment) const;
  RegionAnswer instantiate(RegionId variable, RegionId value,
                           RegionEnvironment &environment) const;
  void clear() { cache.clear(); }

private:
  using Key = std::tuple<RegionId, RegionId, RegionUniverse,
                         std::vector<RegionOutlives>,
                         std::vector<std::pair<RegionId, RegionId>>>;
  std::optional<RegionId> resolve(RegionId region,
                                  const RegionEnvironment &environment) const;
  RegionAnswer prove(RegionId longer, RegionId shorter,
                     const RegionEnvironment &environment,
                     std::vector<RegionOutlives> &active) const;
  const RegionStore &regions;
  std::map<Key, RegionAnswer> cache;
};
enum class Variance { Bivariant, Covariant, Contravariant, Invariant };
bool requiresRegionProof(Type type, const TypeStore &types);
class RegionTypeSolver {
public:
  RegionTypeSolver(TypeStore &types, RegionSolver &regions)
      : types(types), regions(regions) {}
  RegionAnswer coerce(Type source, Type target,
                      const RegionEnvironment &environment);
  Variance variance(Type type, RegionId parameter) const;
  // Whether the last coerce rejected an owned erased payload's bound.
  bool erasedBoundRejected() const { return boundRejected; }

private:
  RegionAnswer compare(Type source, Type target,
                       const RegionEnvironment &environment,
                       std::vector<std::pair<Type, Type>> &active);
  RegionAnswer callable(Type source, Type target,
                        const RegionEnvironment &environment,
                        std::vector<std::pair<Type, Type>> &active);
  Type substitute(Type type,
                  const std::vector<std::pair<RegionId, RegionId>> &bindings);
  Variance varianceFor(Type type, RegionId region, Type parameter) const;
  TypeStore &types;
  RegionSolver &regions;
  bool boundRejected = false;
};
} // namespace mettle
