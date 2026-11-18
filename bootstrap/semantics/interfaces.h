#pragma once

#include "diagnostics/diagnostics.h"
#include "semantics/region_solver.h"
#include "support/overlay_map.h"
#include "types/type.h"
#include <algorithm>
#include <atomic>
#include <cstddef>
#include <functional>
#include <iterator>
#include <map>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <span>
#include <stdexcept>
#include <string_view>
#include <type_traits>
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
template <class T> class DatabaseRecords {
  struct Record {
    explicit Record(T value)
        : owned(std::make_unique<T>(std::move(value))), ready(true) {}
    explicit Record(std::shared_ptr<const T> value)
        : borrowed(std::move(value)), ready(true) {}
    Record(std::size_t input,
           std::shared_ptr<const typename TypeRecords<T>::Loader> loader)
        : loader(std::move(loader)), input(input) {}
    const T &read() const {
      if (borrowed)
        return *borrowed;
      if (!ready.load(std::memory_order_acquire))
        std::call_once(loaded, [&] {
          owned = std::make_unique<T>((*loader)(input));
          loader.reset();
          ready.store(true, std::memory_order_release);
        });
      return *owned;
    }
    mutable std::unique_ptr<T> owned;
    std::shared_ptr<const T> borrowed;
    mutable std::shared_ptr<const typename TypeRecords<T>::Loader> loader;
    std::size_t input = 0;
    mutable std::once_flag loaded;
    mutable std::atomic_bool ready = false;
  };

public:
  using Loader = typename TypeRecords<T>::Loader;
  template <bool Constant> class Iterator {
    using Owner =
        std::conditional_t<Constant, const DatabaseRecords, DatabaseRecords>;

  public:
    using iterator_category = std::forward_iterator_tag;
    using value_type = T;
    using difference_type = std::ptrdiff_t;
    using reference = std::conditional_t<Constant, const T &, T &>;
    using pointer = std::conditional_t<Constant, const T *, T *>;
    Iterator() = default;
    reference operator*() const { return (*owner)[index]; }
    pointer operator->() const { return &**this; }
    Iterator &operator++() {
      ++index;
      return *this;
    }
    Iterator operator++(int) {
      auto previous = *this;
      ++*this;
      return previous;
    }
    bool operator==(const Iterator &) const = default;

  private:
    friend class DatabaseRecords;
    Iterator(Owner *owner, std::size_t index) : owner(owner), index(index) {}
    Owner *owner = nullptr;
    std::size_t index = 0;
  };
  Iterator<false> begin() { return {this, 0}; }
  Iterator<false> end() { return {this, size()}; }
  Iterator<true> begin() const { return {this, 0}; }
  Iterator<true> end() const { return {this, size()}; }
  std::size_t size() const { return records.size(); }
  bool empty() const { return records.empty(); }
  bool isMaterialized(std::size_t index) const {
    const auto &record = records.at(index);
    return record && record->ready.load(std::memory_order_acquire);
  }
  const T &operator[](std::size_t index) const {
    const auto &record = records.at(index);
    if (record)
      return record->read();
    static const T empty{};
    return empty;
  }
  T &operator[](std::size_t index) { return edit(index); }
  const T &at(std::size_t index) const { return (*this)[index]; }
  T &at(std::size_t index) { return edit(index); }
  const T &front() const { return (*this)[0]; }
  T &front() { return edit(0); }
  const T &back() const { return (*this)[size() - 1]; }
  T &back() { return edit(size() - 1); }
  T &edit(std::size_t index) {
    auto &record = records.edit(index);
    if (!record)
      record = std::make_shared<Record>(T{});
    else if (!record.unique() || record->borrowed)
      record = std::make_shared<Record>(record->read());
    record->read();
    return *record->owned;
  }
  std::shared_ptr<const T> retain(std::size_t index) const {
    const auto &record = records.at(index);
    if (record)
      return {record, &record->read()};
    static const auto empty = std::make_shared<const T>();
    return empty;
  }
  void push_back(T value) {
    records.push_back(std::make_shared<Record>(std::move(value)));
  }
  template <class... Args> T &emplace_back(Args &&...args) {
    push_back(T(std::forward<Args>(args)...));
    return edit(size() - 1);
  }
  void push_shared(std::shared_ptr<const T> record) {
    if (!record)
      throw std::invalid_argument("cannot share an empty database record");
    records.push_back(std::make_shared<Record>(std::move(record)));
  }
  void push_uninitialized() { records.push_uninitialized(); }
  void defer(std::size_t index, std::size_t input,
             std::shared_ptr<const Loader> loader) {
    if (!loader || isMaterialized(index))
      throw std::logic_error("invalid deferred database record");
    records.edit(index) = std::make_shared<Record>(input, std::move(loader));
  }
  void reserve(std::size_t size) { records.reserve(size); }
  void resize(std::size_t size) { records.resize(size); }
  void clear() { records.clear(); }
  bool operator==(const DatabaseRecords &other) const {
    return size() == other.size() && std::equal(begin(), end(), other.begin());
  }

private:
  TypeRecords<std::shared_ptr<Record>, true> records;
};
template <class K, class V> class DatabaseMap {
  using Positions = OverlayMap<K, std::size_t>;

public:
  using key_type = K;
  using mapped_type = V;
  using value_type = std::pair<K, V>;
  using Loader = typename DatabaseRecords<value_type>::Loader;
  class Iterator {
  public:
    using iterator_category = std::forward_iterator_tag;
    using value_type = std::pair<K, V>;
    using difference_type = std::ptrdiff_t;
    using reference = const value_type &;
    using pointer = const value_type *;
    Iterator() = default;
    reference operator*() const { return owner->records.at(position->second); }
    pointer operator->() const { return &**this; }
    Iterator &operator++() {
      ++position;
      return *this;
    }
    Iterator operator++(int) {
      auto previous = *this;
      ++*this;
      return previous;
    }
    bool operator==(const Iterator &) const = default;

  private:
    friend class DatabaseMap;
    Iterator(const DatabaseMap *owner, typename Positions::Iterator position)
        : owner(owner), position(position) {}
    const DatabaseMap *owner = nullptr;
    typename Positions::Iterator position;
  };
  DatabaseMap() = default;
  DatabaseMap(const DatabaseMap &) = default;
  DatabaseMap &operator=(const DatabaseMap &) = default;
  DatabaseMap(DatabaseMap &&other) noexcept
      : positions(std::move(other.positions)),
        records(std::move(other.records)),
        imported(std::exchange(other.imported, 0)) {}
  DatabaseMap &operator=(DatabaseMap &&other) noexcept {
    if (this != &other) {
      positions = std::move(other.positions);
      records = std::move(other.records);
      imported = std::exchange(other.imported, 0);
    }
    return *this;
  }
  Iterator begin() const { return {this, positions.begin()}; }
  Iterator end() const { return {this, positions.end()}; }
  Iterator find(const K &key) const { return {this, positions.find(key)}; }
  std::size_t size() const { return positions.size(); }
  bool empty() const { return positions.empty(); }
  const V &at(const K &key) const {
    return records.at(positions.at(key)).second;
  }
  V &operator[](const K &key) {
    if (auto found = positions.find(key); found != positions.end())
      return records.edit(found->second).second;
    auto inserted = emplace(key);
    return records.edit(inserted.first.position->second).second;
  }
  template <class... Args>
  std::pair<Iterator, bool> emplace(K key, Args &&...args) {
    if (auto found = positions.find(key); found != positions.end())
      return {{this, found}, false};
    auto index = records.size();
    records.push_back({key, V(std::forward<Args>(args)...)});
    try {
      auto [position, inserted] = positions.emplace(std::move(key), index);
      return {{this, position}, inserted};
    } catch (...) {
      records.resize(index);
      throw;
    }
  }
  bool defer(K key, std::size_t input, std::shared_ptr<const Loader> loader) {
    if (positions.contains(key))
      return false;
    auto index = records.size();
    records.push_uninitialized();
    try {
      records.defer(index, input, std::move(loader));
      positions.emplace(std::move(key), index);
    } catch (...) {
      records.resize(index);
      throw;
    }
    imported = records.size();
    return true;
  }
  void insertLocal(const DatabaseMap &source) {
    for (const auto &[key, index] : source.positions)
      if (index >= source.imported)
        emplace(key, source.records.at(index).second);
  }
  bool isImported(std::size_t index) const { return index < imported; }
  bool isMaterialized(std::size_t index) const {
    return records.isMaterialized(index);
  }
  const Positions &entries() const { return positions; }
  void freeze() { positions.freeze(); }
  void clear() {
    positions.clear();
    records.clear();
    imported = 0;
  }

private:
  Positions positions;
  DatabaseRecords<value_type> records;
  std::size_t imported = 0;
};
struct Database {
  struct DefinitionHeader {
    std::string name;
    Span span;
    std::vector<std::string> methods;
    std::vector<std::uint32_t> parents;
    std::size_t associated = 0;
  };
  struct ImplementationHeader {
    Type interfaceType = Type::Unknown;
    Span span;
    std::size_t declaration = static_cast<std::size_t>(-1);
    std::vector<std::string> inherent;
    bool fallback = false;
    bool operator==(const ImplementationHeader &) const = default;
  };
  std::shared_ptr<const std::vector<DefinitionHeader>> importedDefinitions;
  std::shared_ptr<const TypeRecords<ImplementationHeader, true>>
      importedImplementations;
  DatabaseRecords<Definition> definitions;
  DatabaseRecords<Implementation> implementations;
  std::string_view definitionName(std::size_t index) const {
    return importedDefinitions && index < importedDefinitions->size() &&
                   !definitions.isMaterialized(index)
               ? (*importedDefinitions)[index].name
               : definitions[index].name;
  }
  bool definitionHasMethod(std::size_t index, std::string_view name) const {
    if (importedDefinitions && index < importedDefinitions->size() &&
        !definitions.isMaterialized(index)) {
      const auto &methods = (*importedDefinitions)[index].methods;
      return std::find(methods.begin(), methods.end(), name) != methods.end();
    }
    const auto &methods = definitions[index].methods;
    return std::any_of(
        methods.begin(), methods.end(),
        [&](const Method &method) { return method.name == name; });
  }
  bool importedImplementation(std::size_t index) const {
    return importedImplementations && index < importedImplementations->size() &&
                   !implementations.isMaterialized(index)
               ? true
               : implementations[index].checkedImport;
  }
  Span implementationSpan(std::size_t index) const {
    return importedImplementations && index < importedImplementations->size() &&
                   !implementations.isMaterialized(index)
               ? (*importedImplementations)[index].span
               : implementations[index].span;
  }
  std::size_t implementationDeclaration(std::size_t index) const {
    return importedImplementations && index < importedImplementations->size() &&
                   !implementations.isMaterialized(index)
               ? (*importedImplementations)[index].declaration
               : implementations[index].declaration;
  }
  // Lazily maintained index of `implementations` by interface declaration;
  // implementations are append-only, so only the new tail is indexed.
  mutable TypeRecords<std::vector<std::size_t>> implementationsByDeclaration;
  mutable std::size_t indexedImplementations = 0;
  const std::vector<std::size_t> &
  implementationsFor(const TypeStore &types, std::uint32_t declaration) const;
  DatabaseRecords<Projection> projections;
  mutable OverlayMap<Type, std::size_t> projectionsByParameter;
  mutable std::size_t indexedProjections = 0;
  const Projection *projectionFor(Type parameter) const;
  DatabaseMap<Type, Implementation> unpinImplementations;
  // Manual (unsafe) positive and negative structural-property declarations
  // keyed by property and nominal origin.
  DatabaseMap<std::pair<Property, Type>, StructuralPropertyDeclaration>
      structuralDeclarations;
  bool argumentsReady = false;
  OverlayMap<Type, Type> callableContracts;
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
        ownedAssumptions(std::move(assumptions)), assumptions(ownedAssumptions),
        regionEnvironment(std::move(regionEnvironment)),
        revealOpaque(revealOpaque) {}
  Solver(std::span<const Obligation> assumptions, TypeStore &types,
         const Database &database, Diagnostics &diagnostics,
         RegionEnvironment regionEnvironment = {}, bool revealOpaque = false)
      : types(types), database(database), diagnostics(diagnostics),
        assumptions(assumptions),
        regionEnvironment(std::move(regionEnvironment)),
        revealOpaque(revealOpaque) {}
  Solver(const Solver &) = delete;
  Solver &operator=(const Solver &) = delete;
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
  std::vector<Obligation> ownedAssumptions;
  std::span<const Obligation> assumptions;
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
  bool matchRegions(const ErasedType &provided, const ErasedType &wanted,
                    std::span<const RegionId> quantified,
                    std::span<const RegionRequirement> requirements,
                    std::vector<RegionBinding> &bindings,
                    RegionEnvironment &environment);
};
} // namespace mettle::interfaces
