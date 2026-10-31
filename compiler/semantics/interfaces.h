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
// a type holding no view with a non-static region.
enum class Property {
  Interface,
  Copy,
  Sized,
  Unpin,
  Transferable,
  Shareable,
  Static
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
  std::uint32_t package = 0;
  Type self = Type::Unknown;
  std::vector<Type> parameters{};
  std::vector<Obligation> superinterfaces{};
  std::vector<Associated> associated{};
  std::vector<Method> methods{};
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
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
};
struct Implementation {
  Type target = Type::Unknown, interfaceType = Type::Unknown;
  Span span;
  std::uint32_t package = 0;
  std::vector<Type> parameters{};
  std::vector<Obligation> requirements{};
  std::map<std::size_t, MethodBinding> methods{};
  std::map<std::size_t, AssociatedValue> associated{};
  std::map<std::string, MethodBinding> inherent{};
  std::vector<RegionId> regions{};
  std::vector<RegionRequirement> regionRequirements{};
  std::vector<TypeBinding> equalities{};
  std::size_t declaration = static_cast<std::size_t>(-1);
};
struct Projection {
  Type parameter, subject, interfaceType;
  std::size_t associated;
  std::vector<Type> arguments{};
  std::vector<RegionId> regionArguments{};
};
struct ConcurrencyDeclaration {
  bool negative = false;
  Implementation implementation{};
};
struct Database {
  std::vector<Definition> definitions;
  std::vector<Implementation> implementations;
  // Lazily maintained index of `implementations` by interface declaration;
  // implementations are append-only, so only the new tail is indexed.
  mutable std::vector<std::vector<std::size_t>> implementationsByDeclaration;
  mutable std::size_t indexedImplementations = 0;
  std::vector<Projection> projections;
  std::map<Type, Implementation> unpinImplementations;
  // Manual (unsafe) positive and negative Transferable/Shareable declarations
  // keyed by property and nominal origin.
  std::map<std::pair<Property, Type>, ConcurrencyDeclaration>
      concurrencyDeclarations;
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
  Type normalize(Type type, std::span<const TypeBinding> bindings, Span span);
  std::optional<Selection> method(Type self, Type interfaceType,
                                  std::size_t slot,
                                  std::span<const Type> arguments, Span span);
  bool coherent();
  std::vector<Obligation> projectionBounds(Type projection, Span span);
  std::optional<Type> implementedInterface(Type subject, Type interfaceType,
                                           Span span);
  bool projectedBinding(Type subject, const ErasedType &wanted,
                        const TypeBinding &required, Span span);
  bool equalities(std::span<const TypeBinding> equations,
                  std::span<const Type> parameters,
                  std::vector<TypeBinding> &bindings, Span span,
                  bool potential = false);
  bool constraints(const Implementation &implementation,
                   std::vector<TypeBinding> &bindings, Span span,
                   std::span<const RegionBinding> regions = {},
                   bool potential = false);
  std::optional<std::vector<TypeBinding>>
  applicable(const Implementation &implementation, Type self, Span span,
             std::vector<RegionBinding> *regions = nullptr,
             bool deferEqualities = false);
  std::optional<std::vector<TypeBinding>>
  match(Type pattern, Type actual, bool symmetric = false,
        RegionEnvironment *regions = nullptr);

private:
  CallableProof callableProof{};
  TypeStore &types;
  const Database &database;
  Diagnostics &diagnostics;
  std::vector<Obligation> assumptions;
  RegionEnvironment regionEnvironment;
  bool revealOpaque = false;
  std::map<std::pair<Type, Type>, std::vector<RegionBinding>> regionSelections;
  std::set<std::pair<Type, Type>> active;
  std::set<Type> normalizing;
  unsigned normalizationDepth = 0;
  std::size_t normalizationSteps = 0;
  std::set<Type> provingUnpin;
  std::set<std::pair<Property, Type>> provingConcurrency;
  bool proveConcurrency(Property property, Type subject, Span span);
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
