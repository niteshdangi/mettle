#pragma once

#include "types/records.h"
#include "types/regions.h"
#include <algorithm>
#include <array>
#include <compare>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <optional>
#include <set>
#include <span>
#include <string>
#include <string_view>
#include <tuple>
#include <type_traits>
#include <unordered_map>
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
enum class VaListAbi { SysV64, Aapcs64, Pointer };
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
  enum class Kind {
    Scalar,
    Aggregate,
    Address,
    Function,
    Text,
    Repeat,
    Pointer,
    TypeIdentity
  };
  Kind kind = Kind::Scalar;
  Type type = Type::Unknown;
  NumericLiteral scalar{};
  std::vector<StaticConstant> fields{};
  int symbol = -1;
  std::vector<std::uint32_t> projections{};
  int selection = -1;
  // Full immutable literal backing; byteOffset and optional fields[0] usize
  // extent describe its view/pointer without changing the backing identity.
  std::string text{};
  std::uint64_t byteOffset = 0;
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
struct OwnedTypeStorage {
  using String = std::string;
  using Features = std::set<std::string>;
  template <class T> using Sequence = std::vector<T>;
};
template <class T> class BorrowedTypeSequence {
public:
  using value_type = T;
  BorrowedTypeSequence() = default;
  template <std::size_t Extent>
  BorrowedTypeSequence(std::span<T, Extent> values) : values(values) {}
  T *begin() { return values.data(); }
  const T *begin() const { return values.data(); }
  T *end() {
    return values.empty() ? values.data() : values.data() + values.size();
  }
  const T *end() const {
    return values.empty() ? values.data() : values.data() + values.size();
  }
  T *data() { return values.data(); }
  const T *data() const { return values.data(); }
  std::size_t size() const { return values.size(); }
  bool empty() const { return values.empty(); }
  T &operator[](std::size_t i) { return values[i]; }
  const T &operator[](std::size_t i) const { return values[i]; }
  T &front() { return values.front(); }
  const T &front() const { return values.front(); }
  T &back() { return values.back(); }
  const T &back() const { return values.back(); }
  operator std::span<T>() { return values; }
  operator std::span<const T>() const { return values; }

private:
  std::span<T> values;
};
struct BorrowedTypeStorage {
  using String = std::string_view;
  using Features = BorrowedTypeSequence<std::string_view>;
  template <class T> using Sequence = BorrowedTypeSequence<T>;
};
template <class Storage> struct BasicCallableParameter {
  Type type;
  ParameterMode mode = ParameterMode::Value;
  typename Storage::String name{};
  bool operator==(const BasicCallableParameter &) const = default;
};
using CallableParameter = BasicCallableParameter<OwnedTypeStorage>;
template <class Storage> struct BasicCallableType {
  typename Storage::template Sequence<BasicCallableParameter<Storage>>
      parameters;
  Type result = Type::Unit;
  Type error = Type::Unknown;
  Type abiResult = Type::Unit;
  typename Storage::template Sequence<std::size_t> resultSources{};
  ParameterMode mode = ParameterMode::Read;
  typename Storage::template Sequence<typename Storage::String> regions{};
  Type environment = Type::Unknown;
  int function = -1;
  typename Storage::String name{};
  typename Storage::template Sequence<RegionId> regionParameters{};
  typename Storage::template Sequence<RegionId> parameterRegions{};
  RegionUniverse regionUniverse = 0;
  typename Storage::template Sequence<RegionRequirement> regionRequirements{};
  bool resultFromEnvironment = false;
  // Hidden environment passing is separate from the source call capability.
  ParameterMode environmentMode = ParameterMode::Read;
  bool unsafeCall = false;
  typename Storage::String abi{};
  bool variadic = false;
  typename Storage::Features targetFeatures{};
};
using CallableType = BasicCallableType<OwnedTypeStorage>;

template <class Storage> struct BasicTypeField {
  typename Storage::String name;
  Type type;
};
using TypeField = BasicTypeField<OwnedTypeStorage>;
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
template <class Storage> struct BasicVariantType {
  typename Storage::String name;
  typename Storage::template Sequence<std::uint32_t> fields;
};
using VariantType = BasicVariantType<OwnedTypeStorage>;
enum class LayoutKind { Native, C, Transparent, Integer };
template <class Storage> struct BasicProductLayout {
  LayoutKind kind = LayoutKind::Native;
  std::uint64_t alignment = 0, packing = 0;
  bool unionType = false;
  Type tag = Type::I32;
  typename Storage::template Sequence<std::uint32_t> pinnedFields{};
  typename Storage::template Sequence<NumericLiteral> discriminants{};
  int unpin = -1;
  typename Storage::template Sequence<std::pair<std::uint32_t, unsigned>>
      unpinConditions{};
  bool conditionalUnpin = false;
};
using ProductLayout = BasicProductLayout<OwnedTypeStorage>;
inline constexpr std::uint32_t unknownPackage = UINT32_MAX;
struct NativeVectorShape {
  Type element;
  unsigned lanes, alignment;
};
template <class Storage> struct BasicProductType {
  typename Storage::String name;
  typename Storage::template Sequence<BasicTypeField<Storage>> fields;
  bool copyRequested;
  // A generic Copy product is Copy only when the type arguments at
  // `copyConditions` are; the other parameters never reach a non-Copy field.
  bool conditionalCopy = false;
  typename Storage::template Sequence<std::size_t> copyConditions{};
  bool hasDestructor = false;
  int destructor = -1;
  AggregateKind kind = AggregateKind::Product;
  typename Storage::template Sequence<BasicVariantType<Storage>> variants{};
  typename Storage::template Sequence<Type> components{};
  int callable = -1;
  typename Storage::template Sequence<Type> genericParameters{};
  Type genericOrigin = Type::Unknown;
  typename Storage::template Sequence<Type> genericArguments{};
  Type arrayCount = Type::Unknown;
  typename Storage::template Sequence<Type> opaqueBounds{};
  std::uint32_t package = unknownPackage;
  Type regionOrigin = Type::Unknown;
  typename Storage::template Sequence<RegionId> regionArguments{};
  Type regionPattern = Type::Unknown;
  BasicProductLayout<Storage> layout{};
  NativeCleanup nativeCleanup = NativeCleanup::None;
  using VectorShape = NativeVectorShape;
  std::optional<VectorShape> vector{};
  bool normalizedFields = false;
};
using ProductType = BasicProductType<OwnedTypeStorage>;
enum class TypeParameterKind { Type, Constant, Value, Expression, Projection };
template <class Storage> struct BasicTypeParameter {
  typename Storage::String name;
  bool copyRequested = false;
  bool sized = true;
  TypeParameterKind kind = TypeParameterKind::Type;
  Type valueType = Type::Unknown;
  // Projection ordinals are identities, not scalar constant payloads.
  std::int64_t value = 0;
  typename Storage::String operation{};
  typename Storage::template Sequence<Type> operands{};
  Type callableConstraint = Type::Unknown;
  // Access parameters of the callable bound without a declared source region.
  typename Storage::template Sequence<std::size_t> callableLocalParameters{};
  typename Storage::template Sequence<RegionId> regionArguments{};
  bool unpin = false;
  bool thin = false;
  NumericLiteral numeric{};
  Type erasedCallableConstraint = Type::Unknown;
};
using TypeParameter = BasicTypeParameter<OwnedTypeStorage>;
struct TypeBinding {
  Type parameter, argument;
  bool operator==(const TypeBinding &) const = default;
};
template <class Storage> struct BasicErasedType {
  typename Storage::String name;
  std::uint32_t declaration = 0;
  typename Storage::template Sequence<Type> arguments{};
  typename Storage::template Sequence<TypeBinding> associated{};
  typename Storage::template Sequence<BasicCallableType<Storage>> methods{};
  typename Storage::template Sequence<Type> methodTypes{};
  typename Storage::template Sequence<Type> methodOwners{};
  typename Storage::template Sequence<std::size_t> methodSlots{};
  typename Storage::template Sequence<Type> parentInterfaces{};
  typename Storage::template Sequence<RegionId> regionArguments{};
  typename Storage::template Sequence<RegionId> regionParameters{};
  RegionUniverse regionUniverse = 0;
  typename Storage::template Sequence<RegionRequirement> regionRequirements{};
  // Lifetime bound of an owned erased payload (`heap any I from r`): every
  // borrow held by the hidden value outlives it. Unspecified outside the
  // region pass and for erased types reached through a view.
  RegionId bound = RegionId::Unspecified;
};
using ErasedType = BasicErasedType<OwnedTypeStorage>;
template <class Storage> struct BasicViewType {
  Type payload;
  ParameterMode mode;
  typename Storage::String name;
  RegionId region = RegionId::Unspecified;
};
using ViewType = BasicViewType<OwnedTypeStorage>;
enum class PointerMetadata { None, ElementCount, Witness, Dependent };
template <class Storage> struct BasicSliceType {
  Type element;
  typename Storage::String name;
  PointerMetadata metadata = PointerMetadata::ElementCount;
};
using SliceType = BasicSliceType<OwnedTypeStorage>;
enum class ImportedTypeKind {
  Product,
  View,
  Pointer,
  Slice,
  Parameter,
  Callable,
  Erased
};
template <class Storage> struct BasicImportedProduct {
  BasicProductType<Storage> descriptor;
  std::optional<BasicCallableType<Storage>> closure;
  typename Storage::template Sequence<Type> coroutineInterior;
};
using ImportedProduct = BasicImportedProduct<OwnedTypeStorage>;
template <class Storage> struct BasicImportedPointer {
  BasicViewType<Storage> descriptor;
};
using ImportedPointer = BasicImportedPointer<OwnedTypeStorage>;
using ImportedTypeDefinition =
    std::variant<ImportedProduct, ViewType, ImportedPointer, SliceType,
                 TypeParameter, CallableType, ErasedType>;
using BorrowedTypeDefinition =
    std::variant<const BasicImportedProduct<BorrowedTypeStorage> *,
                 const BasicViewType<BorrowedTypeStorage> *,
                 const BasicImportedPointer<BorrowedTypeStorage> *,
                 const BasicSliceType<BorrowedTypeStorage> *,
                 const BasicTypeParameter<BorrowedTypeStorage> *,
                 const BasicCallableType<BorrowedTypeStorage> *,
                 const BasicErasedType<BorrowedTypeStorage> *>;
struct ImportedProductView {
  const ProductType &descriptor;
  const CallableType *closure;
  std::span<const Type> coroutineInterior;
};
struct ImportedPointerView {
  const ViewType &descriptor;
};
using ImportedTypeDefinitionView =
    std::variant<ImportedProductView, const ViewType *, ImportedPointerView,
                 const SliceType *, const TypeParameter *, const CallableType *,
                 const ErasedType *>;
struct ImportedSymbolRemap {
  std::span<const std::uint32_t> functions, closures, interfaces, packages;
};
struct ImportedTypeIndex {
  std::span<const Type> key{}, coroutineInterior{};
  std::span<const RegionId> callableRegionParameters{},
      callableParameterRegions{};
  std::span<const RegionRequirement> callableRegionRequirements{};
  Type genericOrigin = Type::Unknown, regionOrigin = Type::Unknown;
  Type payload = Type::Unknown, valueType = Type::Unknown;
  RegionId region = RegionId::Unspecified;
  RegionUniverse regionUniverse = 0;
  ParameterMode mode = ParameterMode::Value;
  TypeParameterKind parameterKind = TypeParameterKind::Type;
  std::array<std::uint64_t, 2> magnitude{};
  std::uint32_t declaration = 0;
  bool closure = false;
};
struct ImportedTypeQuery {
  enum class Kind {
    Generic,
    Regional,
    Aggregate,
    View,
    Pointer,
    Slice,
    Erased,
    Operand,
    Callable,
    Constant,
    NamedProduct
  };
  Kind kind;
  ImportedTypeIndex key;
  std::string_view name{};
};
struct ImportedTypeScalars {
  TypeParameterKind parameterKind = TypeParameterKind::Type;
  Type valueType = Type::Unknown;
  std::uint32_t declaration = 0;
  Type payload = Type::Unknown;
  RegionId region = RegionId::Unspecified;
  AggregateKind aggregateKind = AggregateKind::Product;
  Type genericOrigin = Type::Unknown;
  Type regionOrigin = Type::Unknown;
};
class TypeStore {
public:
  class DefinitionSnapshot;
  // Shells belong only to a transactional staging store until graph validation.
  Type declareImportedType(ImportedTypeKind kind);
  void reserveImportedTypes(std::span<const ImportedTypeKind> kinds,
                            std::shared_ptr<const void> owner);
  void defineImportedType(Type type, ImportedTypeDefinition definition);
  using ImportedDefinitionLoader =
      std::function<ImportedTypeDefinition(std::size_t)>;
  using BorrowedDefinitionLoader =
      std::function<BorrowedTypeDefinition(std::size_t)>;
  using ImportedTypeLookup =
      std::function<std::span<const std::uint32_t>(const ImportedTypeQuery &)>;
  using ImportedTypeScalarLookup =
      std::function<ImportedTypeScalars(std::size_t)>;
  void deferImportedDefinitions(
      std::span<const Type> ids, std::span<const ImportedTypeIndex> index,
      std::shared_ptr<const ImportedDefinitionLoader> loader,
      std::shared_ptr<const BorrowedDefinitionLoader> borrowed = {},
      std::shared_ptr<const void> indexOwner = {},
      ImportedTypeLookup resolve = {}, ImportedTypeScalarLookup scalars = {});
  void remapImportedSymbols(std::span<const Type> types,
                            const ImportedSymbolRemap &symbols);
  ImportedTypeDefinition importedDefinition(Type type) const;
  // Borrows records until mutation detaches or replaces their storage.
  ImportedTypeDefinitionView importedDefinitionView(Type type) const;
  ImportedTypeKind importedKind(Type type) const;
  std::vector<Type> storedTypes() const;
  Type typeAt(std::size_t index) const;
  std::size_t storedTypeCount() const { return entries.size(); }
  std::shared_ptr<const DefinitionSnapshot> snapshotDefinitions() const;
  bool sharesDefinition(Type type, const DefinitionSnapshot &other) const;
  std::vector<Type> referencedTypes(Type type) const;
  void shareInterning();
  Type declareProduct(std::string name, bool copyRequested,
                      AggregateKind kind = AggregateKind::Product);
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
  std::optional<RegionId> unitViewRegion(Type type) const;
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
  void setConditionalCopy(Type type, std::vector<std::size_t> parameters);
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
  template <class Visitor>
  decltype(auto) inspectProduct(Type type, Visitor &&visitor) const {
    return inspectRecord<BasicImportedProduct<BorrowedTypeStorage>>(
        type, products, std::forward<Visitor>(visitor));
  }
  template <class Visitor>
  decltype(auto) inspectView(Type type, Visitor &&visitor) const {
    if (isPointer(type))
      return inspectRecord<BasicImportedPointer<BorrowedTypeStorage>>(
          type, views, std::forward<Visitor>(visitor));
    return inspectRecord<BasicViewType<BorrowedTypeStorage>>(
        type, views, std::forward<Visitor>(visitor));
  }
  template <class Visitor>
  decltype(auto) inspectParameter(Type type, Visitor &&visitor) const {
    return inspectRecord<BasicTypeParameter<BorrowedTypeStorage>>(
        type, parameters, std::forward<Visitor>(visitor));
  }
  template <class Visitor>
  decltype(auto) inspectErased(Type type, Visitor &&visitor) const {
    return inspectRecord<BasicErasedType<BorrowedTypeStorage>>(
        type, erasedTypes, std::forward<Visitor>(visitor));
  }
  std::shared_ptr<const ProductType> retainProduct(Type type) const;
  std::optional<Type> findProduct(std::string_view name) const;
  std::string_view name(Type type) const;
  bool isCopy(Type type) const;
  bool copyProduct(Type type) const;
  bool isUnpin(Type type) const;
  void constrainUnpin(Type type);
  void constrainThin(Type type);
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
  void setPointerBits(unsigned bits) {
    if (pointerBits != bits)
      invalidateRegionErasure();
    pointerBits = bits;
  }
  unsigned targetPointerBits() const { return pointerBits; }
  void setVaListAbi(VaListAbi abi) {
    if (variadicAbi != abi)
      invalidateRegionErasure();
    variadicAbi = abi;
  }
  VaListAbi vaListAbi() const { return variadicAbi; }
  std::vector<TypeField> vaListFields();
  Type projection(Type subject, Type interfaceType, std::size_t associated,
                  std::vector<Type> arguments = {},
                  Type valueType = Type::Unknown, bool copyRequested = false,
                  bool sized = true, std::vector<RegionId> regions = {},
                  bool thin = false);
  bool isProjection(Type type) const;
  std::optional<std::int64_t> constantValue(Type type) const;
  std::optional<NumericLiteral> scalarConstantValue(Type type) const;
  bool isParameter(Type type) const;
  bool isConstant(Type type) const;
  bool isConstParameter(Type type) const;
  bool isSized(Type type, std::span<const Type> assumptions = {}) const;
  bool isThin(Type type) const;
  PointerMetadata pointerMetadata(Type type) const;
  std::optional<Type> unsizedArray(Type source, Type target) const;
  std::optional<std::pair<Type, Type>> erasedTail(Type source,
                                                  Type target) const;
  bool isSymbolic(Type type) const;
  std::vector<Type> typeParameters(Type type,
                                   bool nominalArgumentsOnly = false) const;
  Type nominalOrigin(Type type) const;
  const TypeParameter &parameter(Type type) const;
  void constrainParameter(Type type, bool copyRequested, bool sized);
  void setGenericParameters(Type type, std::vector<Type> parameters);
  Type instantiateProduct(Type origin, std::vector<Type> arguments);
  void refreshProductInstances(std::span<const Type> origins);
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
  std::uint32_t erasedDeclaration(Type type) const;
  Type opaqueType(std::string name, Type hidden, std::vector<Type> bounds,
                  bool copyRequested = false);
  bool isOpaque(Type type) const;
  void setOpaqueBounds(Type type, std::vector<Type> bounds);

private:
  void invalidateRegionErasure() {
    erasedRegions.clear();
    ++regionErasureRevision;
  }
  void invalidateRegionErasure(Type type) {
    if (type.index() >= builtinTypeCount &&
        type.index() - builtinTypeCount < regionErasureTypeCount)
      invalidateRegionErasure();
  }
  std::unordered_map<std::uint32_t, Type> erasedRegions;
  std::uint64_t regionErasureRevision = 0;
  std::size_t regionErasureTypeCount = 0;
  template <class Borrowed, class Owned, class Visitor>
  decltype(auto) inspectRecord(Type type, const TypeRecords<Owned> &records,
                               Visitor &&visitor) const {
    if (auto definition = borrowedDefinition(type))
      if (auto record = std::get_if<const Borrowed *>(&*definition)) {
        const std::shared_ptr<const Borrowed> retained(borrowedDefinitions,
                                                       *record);
        if constexpr (requires { retained->descriptor; })
          return visitor(retained->descriptor);
        else
          return visitor(*retained);
      }
    const auto record =
        records.retain(entries.at(type.index() - builtinTypeCount).index);
    return visitor(*record);
  }
  std::optional<BorrowedTypeDefinition> borrowedDefinition(Type type) const;
  std::span<const Type> retainedCoroutineInterior(Type type) const;
  std::pair<TypeParameterKind, Type> parameterCategory(Type type) const;
  std::shared_ptr<const BorrowedDefinitionLoader> borrowedDefinitions;
  ImportedTypeScalarLookup importedScalars;
  std::size_t borrowedDefinitionCount = 0;
  mutable CoroutineLayout coroutineLayouts;
  std::unordered_map<std::uint32_t, std::vector<Type>> coroutineInteriors;
  using RegionalSubstitution =
      std::pair<Type, std::vector<std::pair<Type, Type>>>;
  std::map<RegionalSubstitution, Type> regionalSubstitutions;
  unsigned regionalSubstitutionDepth = 0;
  unsigned pointerBits = 64;
  VaListAbi variadicAbi = VaListAbi::SysV64;
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
  static EntryKind importedEntryKind(ImportedTypeKind kind);
  EntryKind entryKind(Type type) const {
    auto index = type.index() - builtinTypeCount;
    return index < reservedImportedKinds.size()
               ? importedEntryKind(reservedImportedKinds[index])
               : entries[index].kind;
  }
  struct Entry {
    EntryKind kind;
    std::size_t index;
  };
  TypeRecords<Entry, true> entries;
  std::size_t reservedImportedTypes = 0;
  std::span<const ImportedTypeKind> reservedImportedKinds;
  TypeRecords<ProductType> products;
  TypeRecords<ViewType> views;
  TypeRecords<SliceType> slices;
  RegionStore regionStore;
  TypeRecords<CallableType> callables;
  TypeRecords<TypeParameter> parameters;
  TypeRecords<ErasedType> erasedTypes;
  unsigned instanceDepth = 0;
  // Interning indices. Entries are indexed lazily by fields that are fixed
  // when an entry is created; every candidate is still checked against the
  // full identity predicate, so an index only narrows the search.
  using CallableKey =
      std::tuple<RegionUniverse, std::vector<RegionId>, std::vector<RegionId>,
                 std::vector<RegionRequirement>, std::vector<Type>>;
  using ErasedKey = std::pair<std::uint32_t, std::uint64_t>;
  struct LookupData {
    std::map<Type, std::vector<std::uint32_t>> genericInstances;
    std::map<Type, std::vector<std::uint32_t>> regionInstances;
    std::map<std::vector<Type>, std::vector<std::uint32_t>> aggregates;
    std::map<std::tuple<Type, int, RegionId>, std::uint32_t> views;
    std::map<std::pair<Type, int>, std::uint32_t> pointers;
    std::map<Type, std::uint32_t> slices;
    std::map<ErasedKey, std::vector<std::uint32_t>> erased;
    std::map<std::vector<Type>, std::vector<std::uint32_t>> operands;
    std::map<CallableKey, std::vector<std::uint32_t>> callables;
    std::map<std::pair<Type, std::array<std::uint64_t, 2>>,
             std::vector<std::uint32_t>>
        constants;
  };
  template <class T> struct LookupSequence {
    std::span<const T> values;
    LookupSequence(std::span<const T> values) : values(values) {}
    LookupSequence(const std::vector<T> &values) : values(values) {}
    auto operator<=>(const LookupSequence &other) const {
      return std::lexicographical_compare_three_way(
          values.begin(), values.end(), other.values.begin(),
          other.values.end());
    }
    bool operator==(const LookupSequence &other) const {
      return std::equal(values.begin(), values.end(), other.values.begin(),
                        other.values.end());
    }
  };
  template <class Key> struct ImportedLookupTable {
    std::vector<std::pair<Key, std::uint32_t>> pending;
    std::vector<std::pair<Key, std::size_t>> groups;
    std::vector<std::uint32_t> ordinals;
    void add(Key key, std::uint32_t ordinal) {
      pending.emplace_back(std::move(key), ordinal);
    }
    void seal() {
      std::sort(pending.begin(), pending.end());
      ordinals.reserve(pending.size());
      for (const auto &[key, ordinal] : pending) {
        if (groups.empty() || groups.back().first != key)
          groups.emplace_back(key, ordinals.size());
        ordinals.push_back(ordinal);
      }
      decltype(pending){}.swap(pending);
    }
    std::span<const std::uint32_t> find(const Key &key) const {
      auto entry = std::lower_bound(groups.begin(), groups.end(), key,
                                    [](const auto &group, const Key &value) {
                                      return group.first < value;
                                    });
      if (entry == groups.end() || entry->first != key)
        return {};
      const auto next = std::next(entry);
      const auto end = next == groups.end() ? ordinals.size() : next->second;
      return std::span(ordinals).subspan(entry->second, end - entry->second);
    }
  };
  using ImportedCallableKey =
      std::tuple<RegionUniverse, LookupSequence<RegionId>,
                 LookupSequence<RegionId>, LookupSequence<RegionRequirement>,
                 LookupSequence<Type>>;
  struct ImportedLookupData {
    std::shared_ptr<const void> owner;
    ImportedLookupTable<Type> genericInstances, regionInstances, slices;
    ImportedLookupTable<LookupSequence<Type>> aggregates, operands;
    ImportedLookupTable<std::tuple<Type, int, RegionId>> views;
    ImportedLookupTable<std::pair<Type, int>> pointers;
    ImportedLookupTable<std::uint32_t> erased;
    ImportedLookupTable<ImportedCallableKey> callables;
    ImportedLookupTable<std::pair<Type, std::array<std::uint64_t, 2>>>
        constants;
  };
  struct Lookup {
    std::size_t synced = 0;
    std::shared_ptr<const LookupData> base;
    std::shared_ptr<const ImportedLookupData> imported;
    ImportedTypeLookup resolve;
    LookupData local;
  } lookup;
  void syncLookup();
  static CallableKey callableKey(const CallableType &descriptor);
  static ErasedKey erasedKey(const ErasedType &descriptor);
  template <std::size_t N, class Match>
  std::optional<Type>
  findIndexed(const std::array<std::span<const std::uint32_t>, N> &candidates,
              Match &&match) const {
    std::optional<Type> result;
    for (const auto part : candidates)
      if (auto found = findIndexed(part, match);
          found && (!result || found->index() < result->index()))
        result = found;
    return result;
  }
  template <class Key>
  const auto &importedTable(const std::map<Key, std::vector<std::uint32_t>>
                                LookupData::*table) const {
    if constexpr (std::is_same_v<Key, Type>)
      return table == &LookupData::genericInstances
                 ? lookup.imported->genericInstances
                 : lookup.imported->regionInstances;
    else if constexpr (std::is_same_v<Key, std::vector<Type>>)
      return table == &LookupData::aggregates ? lookup.imported->aggregates
                                              : lookup.imported->operands;
    else if constexpr (std::is_same_v<Key, CallableKey>)
      return lookup.imported->callables;
    else if constexpr (std::is_same_v<Key, ErasedKey>)
      return lookup.imported->erased;
    else
      return lookup.imported->constants;
  }
  template <class Key>
  const auto &
  importedTable(const std::map<Key, std::uint32_t> LookupData::*) const {
    if constexpr (std::is_same_v<Key, Type>)
      return lookup.imported->slices;
    else if constexpr (std::is_same_v<Key, std::pair<Type, int>>)
      return lookup.imported->pointers;
    else
      return lookup.imported->views;
  }
  template <class Key>
  auto
  candidates(const std::map<Key, std::vector<std::uint32_t>> LookupData::*table,
             const Key &key) const {
    auto owned = [&](const LookupData &data, const Key &value) {
      const auto *values = found(data.*table, value);
      return values ? std::span<const std::uint32_t>(*values)
                    : std::span<const std::uint32_t>{};
    };
    auto imported = [&]() -> std::span<const std::uint32_t> {
      if (lookup.resolve)
        return lookup.resolve(importedQuery(table, key));
      if (!lookup.imported)
        return {};
      if constexpr (std::is_same_v<Key, ErasedKey>)
        return importedTable(table).find(key.first);
      else
        return importedTable(table).find(key);
    }();
    if constexpr (std::is_same_v<Key, ErasedKey>) {
      const ErasedKey deferred{key.first, 0};
      return std::array<std::span<const std::uint32_t>, 5>{
          imported,
          lookup.base ? owned(*lookup.base, key)
                      : std::span<const std::uint32_t>{},
          owned(lookup.local, key),
          lookup.base ? owned(*lookup.base, deferred)
                      : std::span<const std::uint32_t>{},
          owned(lookup.local, deferred)};
    } else
      return std::array<std::span<const std::uint32_t>, 3>{
          imported,
          lookup.base ? owned(*lookup.base, key)
                      : std::span<const std::uint32_t>{},
          owned(lookup.local, key)};
  }
  template <class Key>
  std::optional<std::uint32_t>
  interned(const std::map<Key, std::uint32_t> LookupData::*table,
           const Key &key) const {
    const auto *local = found(lookup.local.*table, key);
    const auto *base =
        lookup.base ? found(lookup.base.get()->*table, key) : nullptr;
    const auto imported = lookup.resolve
                              ? lookup.resolve(importedQuery(table, key))
                          : lookup.imported ? importedTable(table).find(key)
                                            : std::span<const std::uint32_t>{};
    std::optional<std::uint32_t> result;
    if (!imported.empty())
      result = imported.front();
    for (const auto *part : {base, local})
      if (part && (!result || *part < *result))
        result = *part;
    return result;
  }
  template <class Key, class Value>
  static ImportedTypeQuery
  importedQuery(const std::map<Key, Value> LookupData::*table, const Key &key) {
    using Kind = ImportedTypeQuery::Kind;
    ImportedTypeQuery result{Kind::Aggregate, {}};
    auto &index = result.key;
    if constexpr (std::is_same_v<Key, Type>) {
      if constexpr (std::is_same_v<Value, std::uint32_t>)
        result.kind = Kind::Slice;
      else
        result.kind = table == &LookupData::genericInstances ? Kind::Generic
                                                             : Kind::Regional;
      index.payload = key;
    } else if constexpr (std::is_same_v<Key, std::vector<Type>>) {
      result.kind =
          table == &LookupData::aggregates ? Kind::Aggregate : Kind::Operand;
      index.key = key;
    } else if constexpr (std::is_same_v<Key, CallableKey>) {
      result.kind = Kind::Callable;
      index.regionUniverse = std::get<0>(key);
      index.callableRegionParameters = std::get<1>(key);
      index.callableParameterRegions = std::get<2>(key);
      index.callableRegionRequirements = std::get<3>(key);
      index.key = std::get<4>(key);
    } else if constexpr (std::is_same_v<Key, ErasedKey>) {
      result.kind = Kind::Erased;
      index.declaration = key.first;
    } else if constexpr (std::is_same_v<Key, std::pair<Type, int>>) {
      result.kind = Kind::Pointer;
      index.payload = key.first;
      index.mode = static_cast<ParameterMode>(key.second);
    } else if constexpr (std::is_same_v<Key, std::tuple<Type, int, RegionId>>) {
      result.kind = Kind::View;
      index.payload = std::get<0>(key);
      index.mode = static_cast<ParameterMode>(std::get<1>(key));
      index.region = std::get<2>(key);
    } else {
      result.kind = Kind::Constant;
      index.valueType = key.first;
      index.magnitude = key.second;
    }
    return result;
  }
  template <class Match>
  std::optional<Type> findIndexed(std::span<const std::uint32_t> candidates,
                                  Match &&match) const {
    std::optional<std::uint32_t> best;
    for (auto i : candidates)
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
class TypeStore::DefinitionSnapshot {
  friend class TypeStore;
  TypeRecords<Entry, true> entries;
  TypeRecords<ProductType> products;
  TypeRecords<ViewType> views;
  TypeRecords<SliceType> slices;
  TypeRecords<CallableType> callables;
  TypeRecords<TypeParameter> parameters;
  TypeRecords<ErasedType> erasedTypes;
  std::unordered_map<std::uint32_t, std::vector<Type>> coroutineInteriors;
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
