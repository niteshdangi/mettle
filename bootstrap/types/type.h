#pragma once

#include "types/regions.h"
#include <array>
#include <compare>
#include <cstdint>
#include <functional>
#include <map>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <utility>
#include <variant>
#include <vector>

namespace mettle {
class TypeId {
public:
  constexpr TypeId() = default;
  constexpr std::uint32_t index() const { return value; }
  constexpr bool operator==(const TypeId &) const = default;
  constexpr auto operator<=>(const TypeId &) const = default;
  static const TypeId Unknown, I32, Bool, Unit, Never, Char, U8;
  static const TypeId I8, I16, I64, I128, Isize, U16, U32, U64, U128, Usize,
      F32, F64;

private:
  friend class TypeStore;
  explicit constexpr TypeId(std::uint32_t index) : value(index) {}
  std::uint32_t value = 0;
};
inline constexpr TypeId TypeId::Unknown{0};
inline constexpr TypeId TypeId::I32{1};
inline constexpr TypeId TypeId::Bool{2};
inline constexpr TypeId TypeId::Unit{3};
inline constexpr TypeId TypeId::Never{4};
inline constexpr TypeId TypeId::Char{5};
inline constexpr TypeId TypeId::U8{6};
inline constexpr TypeId TypeId::I8{7};
inline constexpr TypeId TypeId::I16{8};
inline constexpr TypeId TypeId::I64{9};
inline constexpr TypeId TypeId::I128{10};
inline constexpr TypeId TypeId::Isize{11};
inline constexpr TypeId TypeId::U16{12};
inline constexpr TypeId TypeId::U32{13};
inline constexpr TypeId TypeId::U64{14};
inline constexpr TypeId TypeId::U128{15};
inline constexpr TypeId TypeId::Usize{16};
inline constexpr TypeId TypeId::F32{17};
inline constexpr TypeId TypeId::F64{18};
using Type = TypeId;
inline constexpr std::uint32_t builtinTypeCount = 19;
bool isInteger(Type type);
bool isSignedInteger(Type type);
bool isFloating(Type type);
bool isNumeric(Type type);
unsigned integerWidth(Type type);
// usize/isize take the selected target's pointer width (16, 32 or 64 bits);
// the one-argument forms assume 64.
unsigned integerWidth(Type type, unsigned pointerBits);
// The fixed-width integer with the same width and signedness on that target.
Type integerEquivalent(Type type, unsigned pointerBits);
Type builtinType(std::string_view name);
struct NumericLiteral {
  std::array<std::uint64_t, 2> magnitude{};
  std::string floating{};
  bool negative = false;
  // Exact IEEE bits preserve signed zero and NaN payloads without a text
  // round-trip. Mutually exclusive with floating text and integer magnitude.
  std::optional<std::uint64_t> floatingBits{};
  bool operator==(const NumericLiteral &) const = default;
};
struct NumericConstant {
  Type type = Type::Unknown;
  NumericLiteral literal{};
};
using NumericEvaluator = std::optional<NumericConstant> (*)(
    std::string_view, Type, std::span<const NumericConstant>);
struct StaticConstant {
  // Repeat is one element constant repeated over a compact array.
  enum class Kind { Scalar, Aggregate, Address, Function, Text, Repeat };
  Kind kind = Kind::Scalar;
  Type type = Type::Unknown;
  NumericLiteral scalar{};
  std::vector<StaticConstant> fields{};
  int symbol = -1;
  std::vector<std::uint32_t> projections{};
  int selection = -1;
  // Bytes of a Text or byte-text literal; `type` is its static read view.
  std::string text{};
};
enum class StorageDuration { Automatic, Static };
bool integerLiteralFits(const NumericLiteral &literal, Type type);
bool integerLiteralFits(const NumericLiteral &literal, Type type,
                        unsigned pointerBits);
NumericLiteral integerLiteral(std::int64_t value);
std::string integerLiteralName(const NumericLiteral &value);
int compareIntegers(const NumericLiteral &left, const NumericLiteral &right);
NumericLiteral integerMinimum(Type type);
NumericLiteral integerMaximum(Type type);
NumericLiteral integerMinimum(Type type, unsigned pointerBits);
NumericLiteral integerMaximum(Type type, unsigned pointerBits);
NumericLiteral evaluateIntegerConstant(std::string_view operation, Type type,
                                       const NumericLiteral &left,
                                       const NumericLiteral &right);
NumericLiteral evaluateIntegerConstant(std::string_view operation, Type type,
                                       const NumericLiteral &left,
                                       const NumericLiteral &right,
                                       unsigned pointerBits);
bool validFloatingLiteral(std::string_view spelling);
bool validFloatingConstant(const NumericLiteral &literal, Type type);
bool scalarCastAllowed(Type source, Type target);
struct FloatingPolicy {
  bool reassociate = false, contract = false, noNaNs = false;
  bool noInfinities = false, noSignedZeros = false;
  bool reciprocal = false, approximateFunctions = false;
  bool operator==(const FloatingPolicy &) const = default;
};
enum class ParameterMode { Value, Take, Read, Mut };
struct CallableParameter {
  Type type;
  ParameterMode mode = ParameterMode::Value;
  std::string name{};
  bool operator==(const CallableParameter &) const = default;
};
struct CallableType {
  std::vector<CallableParameter> parameters;
  Type result = Type::Unit;
  Type error = Type::Unknown;
  Type abiResult = Type::Unit;
  std::vector<std::size_t> resultSources{};
  ParameterMode mode = ParameterMode::Read;
  std::vector<std::string> regions{};
  Type environment = Type::Unknown;
  int function = -1;
  std::string name{};
  std::vector<RegionId> regionParameters{};
  std::vector<RegionId> parameterRegions{};
  RegionUniverse regionUniverse = 0;
  std::vector<RegionRequirement> regionRequirements{};
  bool resultFromEnvironment = false;
  // Hidden environment passing is separate from the source call capability.
  ParameterMode environmentMode = ParameterMode::Read;
  bool unsafeCall = false;
  std::string abi{};
  bool variadic = false;
  std::set<std::string> targetFeatures{};
};

struct TypeField {
  std::string name;
  Type type;
};
enum class AggregateKind {
  Product,
  Enumeration,
  Optional,
  Outcome,
  Tuple,
  Array,
  Range,
  Opaque,
  Uninit,
  ManualDrop,
  UnsafeCell,
  Cell,
  RefCell,
  Ref,
  RefMut,
  BorrowError,
  BorrowMutError,
  Pin,
  Atomic,
  Ordering,
  PhantomPinned,
  VarArgs,
  NativeVector,
  // Inline state of a compiler-generated future: components are the output
  // and the coroutine closure; the backend owns its layout.
  Coroutine
};
enum class NativeCleanup { None, RefRelease, RefMutRelease, VaListEnd };
constexpr std::uint32_t cellPayloadField(AggregateKind kind) {
  return kind == AggregateKind::RefCell ? 1u : 0u;
}
struct VariantType {
  std::string name;
  std::vector<std::uint32_t> fields;
};
enum class LayoutKind { Native, C, Transparent, Integer };
struct ProductLayout {
  LayoutKind kind = LayoutKind::Native;
  std::uint64_t alignment = 0, packing = 0;
  bool unionType = false;
  Type tag = Type::I32;
  std::vector<std::uint32_t> pinnedFields{};
  std::vector<NumericLiteral> discriminants{};
  int unpin = -1;
  std::vector<std::pair<std::uint32_t, unsigned>> unpinConditions{};
  bool conditionalUnpin = false;
};
inline constexpr std::uint32_t unknownPackage = UINT32_MAX;
struct ProductType {
  std::string name;
  std::vector<TypeField> fields;
  bool copyRequested;
  bool hasDestructor = false;
  int destructor = -1;
  AggregateKind kind = AggregateKind::Product;
  std::vector<VariantType> variants{};
  std::vector<Type> components{};
  int callable = -1;
  std::vector<Type> genericParameters{};
  Type genericOrigin = Type::Unknown;
  std::vector<Type> genericArguments{};
  Type arrayCount = Type::Unknown;
  std::vector<Type> opaqueBounds{};
  std::uint32_t package = unknownPackage;
  Type regionOrigin = Type::Unknown;
  std::vector<RegionId> regionArguments{};
  Type regionPattern = Type::Unknown;
  ProductLayout layout{};
  NativeCleanup nativeCleanup = NativeCleanup::None;
  struct VectorShape {
    Type element;
    unsigned lanes, alignment;
  };
  std::optional<VectorShape> vector{};
  bool normalizedFields = false;
};
enum class TypeParameterKind { Type, Constant, Value, Expression, Projection };
struct TypeParameter {
  std::string name;
  bool copyRequested = false;
  bool sized = true;
  TypeParameterKind kind = TypeParameterKind::Type;
  Type valueType = Type::Unknown;
  // Projection ordinals are identities, not scalar constant payloads.
  std::int64_t value = 0;
  std::string operation{};
  std::vector<Type> operands{};
  Type callableConstraint = Type::Unknown;
  // Access parameters of the callable bound without a declared source region.
  std::vector<std::size_t> callableLocalParameters{};
  std::vector<RegionId> regionArguments{};
  bool unpin = false;
  NumericLiteral numeric{};
  Type erasedCallableConstraint = Type::Unknown;
};
struct TypeBinding {
  Type parameter, argument;
  bool operator==(const TypeBinding &) const = default;
};
struct ErasedType {
  std::string name;
  std::uint32_t declaration = 0;
  std::vector<Type> arguments{};
  std::vector<TypeBinding> associated{};
  std::vector<CallableType> methods{};
  std::vector<Type> methodTypes{};
  std::vector<Type> methodOwners{};
  std::vector<std::size_t> methodSlots{};
  std::vector<Type> parentInterfaces{};
  std::vector<RegionId> regionArguments{};
  std::vector<RegionId> regionParameters{};
  RegionUniverse regionUniverse = 0;
  std::vector<RegionRequirement> regionRequirements{};
  // Lifetime bound of an owned erased payload (`heap any I from r`): every
  // borrow held by the hidden value outlives it. Unspecified outside the
  // region pass and for erased types reached through a view.
  RegionId bound = RegionId::Unspecified;
};
struct ViewType {
  Type payload;
  ParameterMode mode;
  std::string name;
  RegionId region = RegionId::Unspecified;
};
enum class PointerMetadata { None, ElementCount, Witness, Dependent };
struct SliceType {
  Type element;
  std::string name;
  PointerMetadata metadata = PointerMetadata::ElementCount;
};
enum class ImportedTypeKind {
  Product,
  View,
  Pointer,
  Slice,
  Parameter,
  Callable,
  Erased
};
struct ImportedProduct {
  ProductType descriptor;
  std::optional<CallableType> closure;
  std::vector<Type> coroutineInterior;
};
struct ImportedPointer {
  ViewType descriptor;
};
using ImportedTypeDefinition =
    std::variant<ImportedProduct, ViewType, ImportedPointer, SliceType,
                 TypeParameter, CallableType, ErasedType>;
class TypeStore {
public:
  // Shells belong only to a transactional staging store until graph validation.
  Type declareImportedType(ImportedTypeKind kind);
  void defineImportedType(Type type, ImportedTypeDefinition definition);
  ImportedTypeDefinition importedDefinition(Type type) const;
  ImportedTypeKind importedKind(Type type) const;
  std::vector<Type> storedTypes() const;
  Type declareProduct(std::string name, bool copyRequested);
  Type vectorType(std::string name, Type element, unsigned lanes,
                  unsigned alignment);
  void defineProduct(Type type, std::vector<TypeField> fields);
  void setProductPackage(Type type, std::uint32_t package);
  void setProductLayout(Type type, ProductLayout layout);
  void defineEnumeration(Type type, std::vector<VariantType> variants,
                         std::vector<TypeField> fields);
  // Arrays within these bounds are expanded into one field per element so
  // constant-index places stay precise; larger arrays are compact: one leaf
  // place with an element type and a constant length, like a generic array.
  static constexpr std::uint64_t expandedArrayLimit = 64;
  static constexpr std::uint64_t expandedArrayTotal = 1024;
  static constexpr std::uint64_t droppableArrayElements = 1u << 16;
  Type canonicalCount(Type count);
  // The constant length of a concrete array; empty for a symbolic length.
  std::optional<std::uint64_t> arrayLength(Type array) const;
  bool compactArray(Type array) const;
  bool compactArrayShape(Type payload, std::uint64_t count) const;
  Type structural(AggregateKind kind, std::vector<Type> components,
                  std::uint32_t count = 0);
  bool isSum(Type type) const;
  bool uninhabited(Type type) const;
  bool contains(Type type) const;
  bool isProduct(Type type) const;
  bool isView(Type type) const;
  bool isPointer(Type type) const;
  Type pointerType(Type payload, ParameterMode mode);
  const ViewType &pointer(Type type) const;
  Type viewType(Type payload, ParameterMode mode,
                RegionId region = RegionId::Unspecified);
  RegionStore &regions() { return regionStore; }
  const RegionStore &regions() const { return regionStore; }
  const ViewType &view(Type type) const;
  Type sliceType(Type element);
  bool isSlice(Type type) const;
  const SliceType &slice(Type type) const;
  Type regionalProduct(Type origin, std::vector<TypeField> fields,
                       std::vector<RegionId> arguments,
                       bool normalizedFields = false);
  Type regionalShell(Type origin, std::vector<RegionId> regions,
                     std::vector<Type> arguments, Type pattern = Type::Unknown);
  void setRegionPattern(Type type, Type pattern);
  Type declaredRegions(Type type);
  void setDestructor(Type type, int function);
  // A coroutine state's size and alignment are backend facts: its frame is
  // the lowered body's cleanup frame. The backend installs the resolver for
  // the duration of code generation; it is not part of type identity.
  using CoroutineLayout =
      std::function<std::optional<std::pair<std::uint64_t, std::uint64_t>>(
          Type)>;
  void resolveCoroutineLayouts(CoroutineLayout resolver) const {
    coroutineLayouts = std::move(resolver);
  }
  std::optional<std::pair<std::uint64_t, std::uint64_t>>
  coroutineLayout(Type type) const {
    return coroutineLayouts ? coroutineLayouts(type) : std::nullopt;
  }
  // Types a coroutine body may hold across a suspension, keyed by its
  // symbolic closure; an instance substitutes its generic arguments.
  void setCoroutineInterior(Type closure, std::vector<Type> held);
  std::vector<Type> coroutineInterior(Type closure);
  bool needsDrop(Type type) const;
  // Runtime provenance also includes borrows hidden by an erased payload.
  bool containsViews(Type type, bool includeErasedPayloads = false) const;
  const ProductType &product(Type type) const;
  std::string_view name(Type type) const;
  bool isCopy(Type type) const;
  bool isUnpin(Type type) const;
  void constrainUnpin(Type type);
  Type callableType(CallableType descriptor);
  Type closureType(std::string name, std::vector<TypeField> captures,
                   CallableType descriptor);
  void defineClosure(Type type, std::vector<TypeField> captures,
                     CallableType descriptor);
  bool isCallable(Type type) const;
  bool isFunctionPointer(Type type) const;
  const CallableType &callable(Type type) const;
  bool constrainCallableParameter(Type parameter, Type contract,
                                  std::vector<std::size_t> localParameters);
  bool satisfiesCallable(Type actual, Type contract) const;
  Type declareParameter(std::string name, bool copyRequested,
                        bool sized = true);
  Type declareConstParameter(std::string name, Type valueType);
  void setConstantParameterType(Type parameter, Type valueType);
  Type constant(Type valueType, std::int64_t value);
  Type constant(Type valueType, NumericLiteral value);
  Type constantExpression(std::string operation, std::vector<Type> operands);
  // Pointer width of the compilation target; constant arithmetic on
  // usize/isize wraps and overflows at this width, never the host's.
  void setPointerBits(unsigned bits) { pointerBits = bits; }
  unsigned targetPointerBits() const { return pointerBits; }
  Type projection(Type subject, Type interfaceType, std::size_t associated,
                  std::vector<Type> arguments = {},
                  Type valueType = Type::Unknown, bool copyRequested = false,
                  bool sized = true, std::vector<RegionId> regions = {});
  bool isProjection(Type type) const;
  std::optional<std::int64_t> constantValue(Type type) const;
  std::optional<NumericLiteral> scalarConstantValue(Type type) const;
  bool isParameter(Type type) const;
  bool isConstant(Type type) const;
  bool isSized(Type type) const;
  PointerMetadata pointerMetadata(Type type) const;
  std::optional<Type> unsizedArray(Type source, Type target) const;
  std::optional<std::pair<Type, Type>> erasedTail(Type source,
                                                  Type target) const;
  bool isSymbolic(Type type) const;
  std::vector<Type> typeParameters(Type type) const;
  const TypeParameter &parameter(Type type) const;
  void constrainParameter(Type type, bool copyRequested, bool sized);
  void setGenericParameters(Type type, std::vector<Type> parameters);
  Type instantiateProduct(Type origin, std::vector<Type> arguments);
  void refreshProductInstances();
  Type arrayType(Type payload, Type count);
  Type substitute(Type type, std::span<const TypeBinding> bindings);
  Type substituteRegions(Type type, std::span<const RegionBinding> bindings);
  Type eraseRegions(Type type);
  bool matchesSubstitution(Type pattern, Type actual,
                           std::span<const TypeBinding> bindings) const;
  Type erasedType(ErasedType descriptor);
  Type erasedBound(Type type, RegionId bound);
  void setErasedMethods(Type type, std::vector<CallableType> methods);
  void setErasedDispatch(Type type, std::vector<Type> owners,
                         std::vector<std::size_t> slots);
  void setErasedParents(Type type, std::vector<Type> parents);
  bool isErased(Type type) const;
  const ErasedType &erased(Type type) const;
  Type opaqueType(std::string name, Type hidden, std::vector<Type> bounds,
                  bool copyRequested = false);
  bool isOpaque(Type type) const;
  void setOpaqueBounds(Type type, std::vector<Type> bounds);

private:
  mutable CoroutineLayout coroutineLayouts;
  std::unordered_map<std::uint32_t, std::vector<Type>> coroutineInteriors;
  using RegionalSubstitution =
      std::pair<Type, std::vector<std::pair<Type, Type>>>;
  std::map<RegionalSubstitution, Type> regionalSubstitutions;
  unsigned regionalSubstitutionDepth = 0;
  unsigned pointerBits = 64;
  enum class EntryKind {
    Product,
    View,
    Parameter,
    Callable,
    Erased,
    Opaque,
    Slice,
    Pointer
  };
  struct Entry {
    EntryKind kind;
    std::size_t index;
  };
  std::vector<Entry> entries;
  std::vector<ProductType> products;
  std::vector<ViewType> views;
  std::vector<SliceType> slices;
  RegionStore regionStore;
  std::vector<CallableType> callables;
  std::vector<TypeParameter> parameters;
  std::vector<ErasedType> erasedTypes;
  unsigned instanceDepth = 0;
  // Interning indices. Entries are indexed lazily by fields that are fixed
  // when an entry is created; every candidate is still checked against the
  // full identity predicate, so an index only narrows the search.
  struct Lookup {
    std::size_t synced = 0;
    std::map<Type, std::vector<std::uint32_t>> genericInstances;
    std::map<Type, std::vector<std::uint32_t>> regionInstances;
    std::map<std::vector<Type>, std::vector<std::uint32_t>> aggregates;
    std::map<std::tuple<Type, int, RegionId>, std::uint32_t> views;
    std::map<std::pair<Type, int>, std::uint32_t> pointers;
    std::map<Type, std::uint32_t> slices;
    std::map<std::uint32_t, std::vector<std::uint32_t>> erased;
    std::map<std::vector<Type>, std::vector<std::uint32_t>> operands;
    std::map<std::vector<Type>, std::vector<std::uint32_t>> callables;
    std::map<std::pair<Type, std::array<std::uint64_t, 2>>,
             std::vector<std::uint32_t>>
        constants;
  } lookup;
  void syncLookup();
  static std::vector<Type> callableKey(const CallableType &descriptor);
  template <class Match>
  std::optional<Type> findIndexed(const std::vector<std::uint32_t> *candidates,
                                  Match &&match) const {
    std::optional<std::uint32_t> best;
    if (candidates)
      for (auto i : *candidates)
        if ((!best || i < *best) && match(static_cast<std::size_t>(i)))
          best = i;
    if (!best)
      return std::nullopt;
    return Type(builtinTypeCount + *best);
  }
  template <class Key, class Value>
  static const Value *found(const std::map<Key, Value> &map, const Key &key) {
    auto entry = map.find(key);
    return entry == map.end() ? nullptr : &entry->second;
  }
};
std::string_view typeName(Type type);
// Source spelling (`heap`, `pinned shared`, ...) of an allocation-library
// owner whose first field is the payload pointer, so `Owner<T, ...>` unsizes
// to `Owner<U, ...>` by rebuilding that pointer; empty for other types.
std::string_view ownerSpelling(std::string_view nominal);
// Injective, compilation-independent encoding of a type's identity: nominal
// types by canonical path, bound regions by binder position, `static` kept and
// other regions erased. Display names are not identities (they omit regions).
std::string typeIdentity(const TypeStore &types, Type type);
// Whether a function-pointer type occurs in the type's structure.
bool containsFunctionPointer(const TypeStore &types, Type type);
std::string displayType(Type type);
std::string displayType(const TypeStore &types, Type type,
                        std::span<const Type> namesInMessage = {});
std::optional<std::vector<std::pair<std::uint32_t, Type>>>
staticConstantFields(const TypeStore &types, const StaticConstant &constant);
} // namespace mettle
