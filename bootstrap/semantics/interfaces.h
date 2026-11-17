#pragma once

#include "diagnostics/diagnostics.h"
#include "semantics/region_solver.h"
#include "types/type.h"
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <span>
#include <utility>

namespace mettle::interfaces {
// Transferable/Shareable are structural cross-thread properties; Static marks
// a type holding no view with a non-static region. UnwindSafe and
// RefUnwindSafe are structural panic-safety properties.
enum class Property {
  Interface,
  Copy,
  Sized,
  Unpin,
  Transferable,
  Shareable,
  Static,
  UnwindSafe,
  RefUnwindSafe,
  Freeze,
  Thin
};
struct Obligation {
  Type subject, interfaceType;
  Property property = Property::Interface;
};
struct Associated {
  std::string name;
  Type parameter = Type::Unknown;
  std::vector<Type> parameters{};
  Type defaultValue = Type::Unknown;
  std::vector<Obligation> bounds{};
  std::vector<Obligation> requirements{};
  bool constant = false;
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
  bool asyncFuture = false;
  bool asyncFutureDefaultInferred = false;
  std::vector<TypeBinding> equalities{};
  std::vector<TypeBinding> defaults{};
};
struct Method {
  std::string name;
  int function = -1;
  CallableType signature;
  std::size_t implicitParameters = 0;
  bool dispatchable = true;
};
struct Definition {
  std::string name;
  Span span;
  std::uint32_t package = unknownPackage;
  Type self = Type::Unknown;
  std::vector<Type> parameters{};
  std::vector<Obligation> superinterfaces{};
  std::vector<Associated> associated{};
  std::vector<Method> methods{};
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
  std::vector<Obligation> requirements{};
  std::vector<TypeBinding> equalities{};
  bool unsafeInterface = false;
};
struct MethodBinding {
  int function = -1;
  std::vector<Type> arguments{};
  bool defaultMethod = false;
};
struct AssociatedValue {
  std::vector<Type> parameters{};
  Type value = Type::Unknown;
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
  std::vector<Obligation> requirements{};
  bool fromDefault = false;
  // A constant of non-scalar type is produced by calling this function (an
  // index in the module that declares the implementation); `value` is then
  // only a placeholder constant of that type.
  int initializer = -1;
};
struct Implementation {
  Type target = Type::Unknown, interfaceType = Type::Unknown;
  Span span;
  std::uint32_t package = unknownPackage;
  std::vector<Type> parameters{};
  std::vector<Obligation> requirements{};
  std::map<std::size_t, MethodBinding> methods{};
  std::map<std::size_t, AssociatedValue> associated{};
  std::map<std::string, MethodBinding> inherent{};
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
  std::vector<TypeBinding> equalities{};
  std::size_t declaration = static_cast<std::size_t>(-1);
  // Mounted from a checked library, whose coherence was proven when it was
  // built; only pairs involving the program's own implementations are new.
  bool checkedImport = false;
  // A `@fallback` blanket implementation yields to any other implementation
  // that applies: they never overlap and the other one is selected.
  bool fallback = false;
};
struct Projection {
  Type parameter, subject, interfaceType;
  std::size_t associated;
  std::vector<Type> arguments{};
  std::vector<RegionId> regionArguments{};
};
struct StructuralPropertyDeclaration {
  bool negative = false;
  Implementation implementation{};
};
struct Database {
  std::vector<Definition> definitions;
  TypeRecords<Implementation> implementations;
  // Lazily maintained index of `implementations` by interface declaration;
  // implementations are append-only, so only the new tail is indexed.
  mutable std::vector<std::vector<std::size_t>> implementationsByDeclaration;
  mutable std::size_t indexedImplementations = 0;
  std::vector<Projection> projections;
  mutable std::map<Type, std::size_t> projectionsByParameter;
  mutable std::size_t indexedProjections = 0;
  const Projection *projectionFor(Type parameter) const;
  std::map<Type, Implementation> unpinImplementations;
  // Manual (unsafe) positive and negative structural-property declarations
  // keyed by property and nominal origin.
  std::map<std::pair<Property, Type>, StructuralPropertyDeclaration>
      structuralDeclarations;
  bool argumentsReady = false;
  std::map<Type, Type> callableContracts;
};
std::vector<Type> hierarchy(TypeStore &types, const Database &database,
                            Type subject, Type interfaceType, Span span,
                            Diagnostics &diagnostics);
struct Selection {
  int function = -1;
  std::vector<Type> arguments{};
};
class Solver {
public:
  using CallableProof =
      std::function<bool(Type, Type, const std::vector<TypeBinding> &,
                         std::span<const RegionBinding>, Span)>;
  void setCallableProof(CallableProof proof) {
    callableProof = std::move(proof);
  }
  // Static proofs accept non-static regions and record them for the caller.
  void collectStaticRegions(std::vector<RegionId> *sink) {
    staticRegions = sink;
  }
  void setEqualities(std::span<const TypeBinding> equalities) {
    contextualEqualities.assign(equalities.begin(), equalities.end());
  }
  Solver(TypeStore &types, const Database &database, Diagnostics &diagnostics,
         std::vector<Obligation> assumptions = {},
         RegionEnvironment regionEnvironment = {}, bool revealOpaque = false)
      : types(types), database(database), diagnostics(diagnostics),
        assumptions(std::move(assumptions)),
        regionEnvironment(std::move(regionEnvironment)),
        revealOpaque(revealOpaque) {}
  bool prove(const Obligation &obligation, Span span, bool report = true);
  bool wellFormedInterface(Type subject, Type interfaceType, Span span,
                           bool report = true);
  Type checkedProjection(Type projection, Span span, bool report = true);
  Type normalize(Type type, std::span<const TypeBinding> bindings, Span span);
  Type normalizeUncached(Type type, std::span<const TypeBinding> bindings,
                         Span span);
  // The function producing the aggregate value of associated constant `slot`.
  std::optional<Selection> constantInitializer(Type self, Type interfaceType,
                                               std::size_t slot, Span span);
  std::optional<Selection> method(Type self, Type interfaceType,
                                  std::size_t slot,
                                  std::span<const Type> arguments, Span span);
  bool coherent();
  std::vector<Obligation> projectionBounds(Type projection, Span span);
  std::optional<Type>
  implementedInterface(Type subject, Type interfaceType, Span span,
                       std::span<const Type> inferenceParameters = {});
  std::optional<Type> inferredSubject(Type partial, Type interfaceType,
                                      Span span);
  bool projectedBinding(Type subject, const ErasedType &wanted,
                        const TypeBinding &required, Span span);
  bool equalities(std::span<const TypeBinding> equations,
                  std::span<const Type> parameters,
                  std::vector<TypeBinding> &bindings, Span span,
                  bool potential = false,
                  std::span<const TypeBinding> callableResults = {});
  bool constraints(const Implementation &implementation,
                   std::vector<TypeBinding> &bindings, Span span,
                   std::span<const RegionBinding> regions = {},
                   bool potential = false);
  std::optional<std::vector<TypeBinding>>
  applicable(const Implementation &implementation, Type self, Span span,
             std::vector<RegionBinding> *regions = nullptr,
             bool deferEqualities = false, bool potential = false);
  std::optional<std::vector<TypeBinding>>
  match(Type pattern, Type actual, bool symmetric = false,
        RegionEnvironment *regions = nullptr, bool partialActual = false);

private:
  CallableProof callableProof{};
  std::vector<RegionId> *staticRegions = nullptr;
  TypeStore &types;
  const Database &database;
  Diagnostics &diagnostics;
  std::vector<Obligation> assumptions;
  RegionEnvironment regionEnvironment;
  bool revealOpaque = false;
  std::map<std::pair<Type, Type>, std::vector<RegionBinding>> regionSelections;
  // Outcomes of `implementation` that depend on nothing but the two types.
  std::map<Type, Type> normalized;
  std::map<std::pair<Type, Type>,
           std::optional<
               std::pair<const Implementation *, std::vector<TypeBinding>>>>
      selected;
  std::set<std::pair<Type, Type>> active;
  std::set<std::pair<Type, Type>> checkingArguments;
  std::set<Type> normalizing;
  unsigned normalizationDepth = 0;
  std::size_t normalizationSteps = 0;
  std::set<Type> provingUnpin;
  std::set<std::pair<Property, Type>> provingStructuralProperties;
  bool proveStructuralProperty(Property property, Type subject, Span span);
  std::vector<TypeBinding> contextualEqualities;
  std::size_t steps = 0;
  bool regionInconclusive = false;
  bool limitReported = false;
  std::optional<std::pair<const Implementation *, std::vector<TypeBinding>>>
  implementation(Type self, Type interfaceType, Span span, bool report);
  bool someImplementationCouldApply(Type subject, Type interfaceType);
  const std::vector<std::size_t> &candidatesFor(std::uint32_t declaration);
  bool matchRegions(const ErasedType &provided, const ErasedType &wanted,
                    std::span<const RegionId> quantified,
                    std::span<const RegionRequirement> requirements,
                    std::vector<RegionBinding> &bindings,
                    RegionEnvironment &environment);
};
} // namespace mettle::interfaces
