#pragma once

#include "ir/ir.h"
#include "metadata/references.h"
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <span>

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
  // View paths absent from every returned value.
  std::set<ViewPath> absentReturns;
  std::map<ViewPath, std::set<Place>> disjointWrites;
  // These roots are resolved static identities, not callee-local slots.
  std::map<ViewPath, std::set<Place>> staticReturns;
  bool operator==(const FunctionEffects &) const = default;
};
// Per-function effect summaries. Reads are optionally recorded so the fixpoint
// can re-analyze only the functions that consulted a changed summary.
std::optional<std::vector<std::uint8_t>>
encodeEffects(const FunctionEffects &effects,
              const metadata::EncodeReferences &references);
std::optional<FunctionEffects>
decodeEffects(std::span<const std::uint8_t> bytes,
              const metadata::DecodeReferences &references);
class EffectSummaries {
public:
  using Loader = std::function<std::optional<FunctionEffects>(std::size_t)>;
  using Shared = std::shared_ptr<const FunctionEffects>;
  explicit EffectSummaries(std::size_t count) : items(count) {}
  const FunctionEffects &operator[](std::size_t index) const {
    return read(index, items[index]);
  }
  const FunctionEffects &at(std::size_t index) const {
    return read(index, items.at(index));
  }
  const FunctionEffects &get(std::size_t index) const {
    return items[index] ? *items[index] : none();
  }
  const Shared &shared(std::size_t index) const { return items[index]; }
  void set(std::size_t index, FunctionEffects value) {
    items[index] = std::make_shared<const FunctionEffects>(std::move(value));
  }
  void share(std::size_t index, Shared value) {
    items[index] = std::move(value);
  }
  static const FunctionEffects &none() {
    static const FunctionEffects empty;
    return empty;
  }
  void record(std::set<std::size_t> *sink) const { reads = sink; }
  // Summaries a loader supplies are final: their functions are never analysed.
  void persisted(Loader load) {
    loader = std::move(load);
    attempted.assign(items.size(), false);
    stored.assign(items.size(), false);
  }
  bool load(std::size_t index) const {
    if (loader && !attempted[index]) {
      attempted[index] = true;
      if (auto effects = loader(index)) {
        items[index] =
            std::make_shared<const FunctionEffects>(std::move(*effects));
        stored[index] = true;
        if (bodies.size() <= index)
          bodies.resize(items.size());
        bodies[index] = true;
      }
    }
    return supplied(index);
  }
  bool supplied(std::size_t index) const {
    return index < stored.size() && stored[index];
  }
  // The summary was computed from a CFG the program record does not hold.
  bool bodied(std::size_t index) const {
    return index < bodies.size() && bodies[index];
  }
  void setBodied(std::size_t index, bool value) {
    if (bodies.size() <= index)
      bodies.resize(items.size());
    bodies[index] = value;
  }

private:
  mutable std::vector<bool> bodies, attempted, stored;
  Loader loader;
  const FunctionEffects &read(std::size_t index, const Shared &value) const {
    if (reads)
      reads->insert(index);
    load(index);
    return value ? *value : none();
  }
  mutable std::vector<Shared> items;
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
  Origins disjointReplacements;
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
  Origins replacedViews;
  bool empty() const {
    return uses.empty() && defines.empty() && targets.empty() && dead.empty() &&
           movedViews.empty() && drops.empty() && overwrites.empty() &&
           replacedViews.empty();
  }
};
struct OriginInfo {
  std::map<int, Loan> loans;
  std::vector<std::map<std::size_t, Point>> points;
  std::map<int, ViewOrigins> values;
  std::vector<Origins> returns;
  std::vector<Origins> storedIn;
  std::map<int, int> externalSources;
  std::map<int, Place> externalPlaces;
  FunctionEffects effects;
  std::vector<std::pair<Origins, Span>> escapes;
  const Point &point(std::size_t block, std::size_t instruction) const {
    static const Point empty;
    const auto found = points[block].find(instruction);
    return found == points[block].end() ? empty : found->second;
  }
  const ViewOrigins &value(int id) const {
    static const ViewOrigins empty;
    const auto found = values.find(id);
    return found == values.end() ? empty : found->second;
  }
};
OriginInfo origins(const ir::Function &function, const ir::Program &program,
                   const EffectSummaries &summaries);
std::vector<std::size_t> reversePostorder(const ir::Function &function);
Origins ancestors(Origins origins, const std::map<int, Loan> &loans);
// Like ancestors, but without the parents a loan only keeps unavailable.
Origins strongAncestors(const Origins &origins,
                        const std::map<int, Loan> &loans);
bool disjointLoans(const Origins &authority, int other,
                   const std::map<int, Loan> &loans);
} // namespace mettle::analysis
