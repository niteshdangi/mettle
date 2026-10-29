#pragma once

#include "types/type.h"
#include <cstddef>
#include <map>
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
  explicit RegionSolver(const RegionStore &regions, std::size_t budget = 4096)
      : regions(regions), budget(budget) {}
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
  RegionId resolve(RegionId region, const RegionEnvironment &environment,
                   std::size_t &remaining) const;
  RegionAnswer prove(RegionId longer, RegionId shorter,
                     const RegionEnvironment &environment,
                     std::vector<RegionOutlives> &active,
                     std::size_t &remaining) const;
  const RegionStore &regions;
  std::size_t budget;
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

private:
  RegionAnswer compare(Type source, Type target,
                       const RegionEnvironment &environment,
                       std::vector<std::pair<Type, Type>> &active,
                       std::size_t &remaining);
  RegionAnswer callable(Type source, Type target,
                        const RegionEnvironment &environment,
                        std::vector<std::pair<Type, Type>> &active,
                        std::size_t &remaining);
  Type substitute(Type type,
                  const std::vector<std::pair<RegionId, RegionId>> &bindings);
  std::optional<Variance> varianceFor(Type type, RegionId region,
                                      Type parameter,
                                      std::size_t &remaining) const;
  TypeStore &types;
  RegionSolver &regions;
};
} // namespace mettle
