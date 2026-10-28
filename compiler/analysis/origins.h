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
  ViewEffects writeDependencies;
  std::set<Place> overwrites;
  std::map<ViewPath, std::set<Place>> returns;
  bool operator==(const FunctionEffects &) const = default;
};
using EffectSummaries = std::vector<FunctionEffects>;
struct Target {
  Place place;
  Origins authority;
  auto operator<=>(const Target &) const = default;
};
struct Loan {
  ParameterMode mode = ParameterMode::Read;
  std::set<Target> targets;
  Origins parents;
  int parameter = -1;
  bool reserved = false;
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
} // namespace mettle::analysis
