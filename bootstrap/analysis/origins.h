#pragma once

#include "ir/ir.h"
#include <map>
#include <set>

namespace mettle::analysis {
using Origins = std::set<int>;
using ViewPath = std::vector<Projection>;
using ViewOrigins = std::map<ViewPath, Origins>;
using ViewEffects = std::map<Place, std::set<Place>>;
struct FunctionEffects {
  ViewEffects writes;
  ViewEffects wildWrites;
  // Wild writes whose source loans stay live with the destination regardless
  // of the borrowed place's type (`Within` retention).
  ViewEffects retained;
  ViewEffects writeDependencies;
  std::set<Place> overwrites;
  std::map<ViewPath, std::set<Place>> returns;
  // These roots are resolved static identities, not callee-local slots.
  std::map<ViewPath, std::set<Place>> staticReturns;
  bool operator==(const FunctionEffects &) const = default;
};
// Per-function effect summaries. Reads are optionally recorded so the fixpoint
// can re-analyze only the functions that consulted a changed summary.
class EffectSummaries {
public:
  explicit EffectSummaries(std::size_t count) : items(count) {}
  const FunctionEffects &operator[](std::size_t index) const {
    return read(index, items[index]);
  }
  const FunctionEffects &at(std::size_t index) const {
    return read(index, items.at(index));
  }
  FunctionEffects &slot(std::size_t index) { return items[index]; }
  void record(std::set<std::size_t> *sink) const { reads = sink; }

private:
  const FunctionEffects &read(std::size_t index,
                              const FunctionEffects &value) const {
    if (reads)
      reads->insert(index);
    return value;
  }
  std::vector<FunctionEffects> items;
  mutable std::set<std::size_t> *reads = nullptr;
};
struct Target {
  Place place;
  Origins authority;
  auto operator<=>(const Target &) const = default;
};
struct Loan {
  ParameterMode mode = ParameterMode::Read;
  std::set<Target> targets;
  // Referents of exclusive views stored in the borrowed places: the borrow
  // freezes them against access that does not go through it.
  std::set<Target> frozen;
  Origins parents;
  // Parents that keep this loan's referents unavailable while live but whose
  // own storage the loan does not borrow: a result carrying only the exclusive
  // views stored in a borrowed container.
  Origins borrowed;
  Origins disjointOutputs;
  int parameter = -1;
  bool reserved = false;
  bool interiorRoot = false;
  bool interiorPayload = false;
};
struct Point {
  Origins uses, defines;
  std::set<Target> targets;
  std::vector<Place> dead;
  Origins movedViews;
  Origins drops;
  std::set<Place> overwrites;
};
struct OriginInfo {
  std::map<int, Loan> loans;
  std::vector<std::vector<Point>> points;
  std::vector<ViewOrigins> values;
  std::vector<Origins> returns;
  std::map<int, int> externalSources;
  std::map<int, Place> externalPlaces;
  FunctionEffects effects;
  std::vector<std::pair<Origins, Span>> escapes;
};
OriginInfo origins(const ir::Function &function, const ir::Program &program,
                   const EffectSummaries &summaries);
Origins ancestors(const Origins &origins, const std::map<int, Loan> &loans);
// Like ancestors, but without the parents a loan only keeps unavailable.
Origins strongAncestors(const Origins &origins,
                        const std::map<int, Loan> &loans);
} // namespace mettle::analysis
