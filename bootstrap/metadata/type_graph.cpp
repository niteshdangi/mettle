#include "metadata/type_graph.h"
#include "support/limits.h"
#include <algorithm>
#include <bit>
#include <exception>
#include <limits>
#include <map>
#include <memory_resource>
#include <mutex>
#include <set>
#include <stdexcept>
#include <thread>
#include <tuple>
#include <type_traits>
#include <unordered_map>
#include <unordered_set>

namespace mettle::metadata {
namespace {
constexpr std::array primitiveTypes{
    Type::Unknown, Type::I32,   Type::Bool, Type::Unit, Type::Never,
    Type::Char,    Type::U8,    Type::I8,   Type::I16,  Type::I64,
    Type::I128,    Type::Isize, Type::U16,  Type::U32,  Type::U64,
    Type::U128,    Type::Usize, Type::F32,  Type::F64};
constexpr auto primitiveCount =
    static_cast<std::uint32_t>(primitiveTypes.size());
struct InvalidGraph {
  std::string message;
};
[[noreturn]] void reject(std::string message) {
  throw InvalidGraph{std::move(message)};
}
template <class E> constexpr unsigned lastTag() {
  if constexpr (std::is_same_v<E, ImportedTypeKind>)
    return static_cast<unsigned>(ImportedTypeKind::Erased);
  else if constexpr (std::is_same_v<E, AggregateKind>)
    return static_cast<unsigned>(AggregateKind::Coroutine);
  else if constexpr (std::is_same_v<E, TypeParameterKind>)
    return static_cast<unsigned>(TypeParameterKind::Projection);
  else if constexpr (std::is_same_v<E, ParameterMode>)
    return static_cast<unsigned>(ParameterMode::Mut);
  else if constexpr (std::is_same_v<E, NativeCleanup>)
    return static_cast<unsigned>(NativeCleanup::VaListEnd);
  else if constexpr (std::is_same_v<E, LayoutKind>)
    return static_cast<unsigned>(LayoutKind::Integer);
  else if constexpr (std::is_same_v<E, PointerMetadata>)
    return static_cast<unsigned>(PointerMetadata::Dependent);
  else {
    static_assert(std::is_same_v<E, RegionKind>);
    return static_cast<unsigned>(RegionKind::Intersection);
  }
}
template <class A> void record(A &a, NumericLiteral &r) {
  a(r.magnitude[0], r.magnitude[1], r.floating, r.negative, r.floatingBits);
}
template <class A, class Storage>
void record(A &a, BasicCallableParameter<Storage> &r) {
  a(r.type, r.mode);
  a.name(r.name);
}
template <class A> void record(A &a, RegionRequirement &r) {
  a(r.longer, r.shorter);
}
template <class A, class Storage>
void record(A &a, BasicCallableType<Storage> &r) {
  a(r.parameters, r.result, r.error, r.abiResult, r.resultSources, r.mode);
  a.names(r.regions);
  a(r.environment);
  a.closure(r.function);
  a.name(r.name);
  a(r.regionParameters, r.parameterRegions);
  a.universe(r.regionUniverse);
  a(r.regionRequirements, r.resultFromEnvironment, r.environmentMode,
    r.unsafeCall, r.abi, r.variadic);
  a.features(r.targetFeatures);
}
template <class A, class Storage>
void record(A &a, BasicTypeField<Storage> &r) {
  a(r.name, r.type);
}
template <class A, class Storage>
void record(A &a, BasicVariantType<Storage> &r) {
  a(r.name, r.fields);
}
template <class A, class Storage>
void record(A &a, BasicProductLayout<Storage> &r) {
  a(r.kind, r.alignment, r.packing, r.unionType, r.tag, r.pinnedFields,
    r.discriminants, r.unpin, r.unpinConditions, r.conditionalUnpin);
}
template <class A> void record(A &a, ProductType::VectorShape &r) {
  a(r.element, r.lanes, r.alignment);
}
template <class A, class Storage>
void record(A &a, BasicProductType<Storage> &r) {
  a(r.name, r.fields, r.copyRequested, r.conditionalCopy, r.copyConditions,
    r.hasDestructor);
  a.function(r.destructor);
  a(r.kind, r.variants, r.components, r.genericParameters, r.genericOrigin,
    r.genericArguments, r.arrayCount, r.opaqueBounds);
  a.package(r.package);
  a(r.regionOrigin, r.regionArguments, r.regionPattern, r.layout,
    r.nativeCleanup, r.vector, r.normalizedFields);
}
template <class A, class Storage>
void record(A &a, BasicTypeParameter<Storage> &r) {
  a(r.name, r.copyRequested, r.sized, r.thin, r.kind, r.valueType, r.value,
    r.operation, r.operands, r.callableConstraint, r.callableLocalParameters,
    r.regionArguments, r.unpin, r.numeric, r.erasedCallableConstraint);
}
template <class A> void record(A &a, TypeBinding &r) {
  a(r.parameter, r.argument);
}
template <class A, class Storage>
void record(A &a, BasicErasedType<Storage> &r) {
  a(r.name);
  a.interface(r.declaration);
  a(r.arguments, r.associated, r.methods, r.methodTypes, r.methodOwners,
    r.methodSlots, r.parentInterfaces, r.regionArguments, r.regionParameters);
  a.universe(r.regionUniverse);
  a(r.regionRequirements, r.bound);
}
template <class A, class Storage> void record(A &a, BasicViewType<Storage> &r) {
  a(r.payload, r.mode, r.name, r.region);
}
template <class A, class Storage>
void record(A &a, BasicSliceType<Storage> &r) {
  a(r.element, r.name, r.metadata);
}
template <class A, class Storage>
void record(A &a, BasicImportedProduct<Storage> &r) {
  a(r.descriptor, r.closure, r.coroutineInterior);
}
template <class A, class Storage>
void record(A &a, BasicImportedPointer<Storage> &r) {
  a(r.descriptor);
}
template <class A> void record(A &a, DefinitionIdentity &r) {
  a(r.package, r.definition, r.parameterOrdinal);
}

template <class Derived> struct Fields {
  template <class... T> void operator()(T &...values) {
    (static_cast<Derived *>(this)->value(values), ...);
  }
  template <class T> void name(T &value) {
    static_cast<Derived *>(this)->value(value);
  }
  template <class T> void names(T &value) {
    static_cast<Derived *>(this)->value(value);
  }
  template <class T> void features(T &value) {
    static_cast<Derived *>(this)->value(value);
  }
};
struct Graph {
  const TypeStore &types;
  std::vector<Type> typeList;
  std::map<Type, std::uint32_t> typeRefs;
  std::vector<RegionId> regionList;
  std::map<RegionId, std::uint32_t> regionRefs;
  std::vector<RegionUniverse> universes{0};
  std::map<RegionUniverse, std::uint32_t> universeRefs{{0, 0}};
  std::vector<RegionBinder> binders;
  std::map<RegionBinder, std::uint32_t> binderRefs;
  std::vector<RegionUniverse> binderUniverses;

  explicit Graph(const TypeStore &types) : types(types) {}
  std::uint32_t type(Type id) {
    if (id != Type::Unknown && !types.contains(id))
      reject("dangling exported type reference");
    if (id.index() < builtinTypeCount) {
      auto primitive =
          std::find(primitiveTypes.begin(), primitiveTypes.end(), id);
      if (primitive == primitiveTypes.end())
        reject("unrepresented primitive type");
      return static_cast<std::uint32_t>(primitive - primitiveTypes.begin());
    }
    auto [entry, added] = typeRefs.emplace(
        id, primitiveCount + static_cast<std::uint32_t>(typeList.size()));
    if (added) {
      if (typeList.size() >= limits::products)
        reject("type graph exceeds compiler type count limit");
      typeList.push_back(id);
    }
    return entry->second;
  }
  std::uint32_t universe(RegionUniverse id) {
    if (id >= types.regions().universeCount())
      reject("dangling exported region universe");
    if (auto found = universeRefs.find(id); found != universeRefs.end())
      return found->second;
    std::vector<RegionUniverse> chain;
    while (!universeRefs.contains(id)) {
      chain.push_back(id);
      auto parent = types.regions().universeParent(id);
      if (parent >= id)
        reject("cyclic exported region universe");
      id = parent;
    }
    for (auto i = chain.rbegin(); i != chain.rend(); ++i) {
      universeRefs.emplace(*i, static_cast<std::uint32_t>(universes.size()));
      universes.push_back(*i);
    }
    return universeRefs.at(chain.front());
  }
  std::uint32_t binder(RegionBinder id, RegionUniverse scope) {
    if (!id)
      reject("missing exported region binder");
    universe(scope);
    auto [entry, added] =
        binderRefs.emplace(id, static_cast<std::uint32_t>(binders.size()));
    if (added) {
      binders.push_back(id);
      binderUniverses.push_back(scope);
    } else if (binderUniverses[entry->second] != scope)
      reject("region binder has inconsistent universes");
    return entry->second;
  }
  std::uint32_t region(RegionId id) {
    if (!types.regions().contains(id))
      reject("dangling exported region reference");
    if (id == RegionId::Unspecified)
      return 0;
    if (id == RegionId::Static)
      return 1;
    auto [entry, added] = regionRefs.emplace(
        id, 2 + static_cast<std::uint32_t>(regionList.size()));
    if (added) {
      regionList.push_back(id);
      const auto &r = types.regions().get(id);
      if (r.kind != RegionKind::Intersection)
        binder(r.binder, r.universe);
    }
    return entry->second;
  }
};
struct Writer : Fields<Writer> {
  struct SymbolFixup {
    std::size_t offset;
    SymbolKind kind;
    std::uint32_t index;
    unsigned width;
  };
  Graph *graph = nullptr;
  const TypeGraphSymbols *symbols = nullptr;
  std::vector<std::uint8_t> bytes;
  bool discardBytes = false;
  std::uint64_t *fingerprint = nullptr;
  std::vector<Type> *typeReferences = nullptr;
  const std::function<Type(Type)> *typeMapper = nullptr;
  std::vector<SymbolFixup> *symbolFixups = nullptr;
  bool omitCallableNames = false;
  Writer() = default;
  Writer(Graph &graph, const TypeGraphSymbols &symbols)
      : graph(&graph), symbols(&symbols) {}
  void byte(std::uint8_t b) {
    if (fingerprint)
      *fingerprint = (*fingerprint ^ b) * 1099511628211ull;
    if (discardBytes)
      return;
    if (bytes.size() >= limits::sourceBytes)
      reject("type graph exceeds source byte limit");
    bytes.push_back(b);
  }
  template <class T> void integer(T n) {
    std::array<std::uint8_t, sizeof(T)> encoded;
    for (unsigned i = 0; i != encoded.size(); ++i)
      encoded[i] = static_cast<std::uint8_t>(n >> (8 * i));
    if (fingerprint) {
      auto hash = *fingerprint;
      for (auto byte : encoded)
        hash = (hash ^ byte) * 1099511628211ull;
      *fingerprint = hash;
    }
    if (discardBytes)
      return;
    if (bytes.size() > limits::sourceBytes - encoded.size())
      reject("type graph exceeds source byte limit");
    bytes.insert(bytes.end(), encoded.begin(), encoded.end());
  }
  void u32(std::uint32_t n) { integer(n); }
  void u64(std::uint64_t n) { integer(n); }
  template <class T> void value(T &n) {
    if constexpr (std::is_same_v<T, bool>)
      byte(n ? 1 : 0);
    else if constexpr (std::is_enum_v<T>) {
      if (static_cast<unsigned>(n) > lastTag<T>())
        reject("invalid exported semantic tag");
      byte(static_cast<std::uint8_t>(n));
    } else if constexpr (std::is_integral_v<T>)
      u64(static_cast<std::uint64_t>(n));
    else
      record(*this, n);
  }
  template <class T> void value(const T &n) { value(const_cast<T &>(n)); }
  void value(Type &type) {
    auto mapped = typeMapper ? (*typeMapper)(type) : type;
    if (typeReferences)
      typeReferences->push_back(mapped);
    u32(graph ? graph->type(mapped) : mapped.index());
  }
  void value(RegionId &region) {
    u32(graph ? graph->region(region) : region.index());
  }
  void universe(RegionUniverse &universe) {
    u32(graph ? graph->universe(universe) : universe);
  }
  void value(std::string &text) {
    std::string_view view = text;
    value(view);
  }
  void value(std::string_view text) {
    if (text.size() > limits::sourceBytes)
      reject("type graph string exceeds source byte limit");
    u32(static_cast<std::uint32_t>(text.size()));
    if (fingerprint) {
      auto hash = *fingerprint;
      for (unsigned char c : text)
        hash = (hash ^ c) * 1099511628211ull;
      *fingerprint = hash;
    }
    if (discardBytes)
      return;
    if (text.size() > limits::sourceBytes - bytes.size())
      reject("type graph exceeds source byte limit");
    bytes.insert(bytes.end(), text.begin(), text.end());
  }
  template <class T> void value(std::vector<T> &items) {
    if (items.size() > limits::sourceBytes)
      reject("type graph sequence exceeds source byte limit");
    u32(static_cast<std::uint32_t>(items.size()));
    for (auto &item : items)
      value(item);
  }
  template <class T> void value(std::span<T> items) {
    if (items.size() > limits::sourceBytes)
      reject("type graph sequence exceeds source byte limit");
    u32(static_cast<std::uint32_t>(items.size()));
    for (const auto &item : items)
      value(item);
  }
  template <class T> void value(BorrowedTypeSequence<T> items) {
    value(std::span<T>(items));
  }
  template <class T> void name(T &text) {
    if (omitCallableNames)
      u32(0);
    else
      value(text);
  }
  template <class T> void names(T &items) {
    u32(static_cast<std::uint32_t>(items.size()));
    for (auto &item : items)
      name(item);
  }
  template <class T> void value(std::optional<T> &item) {
    byte(item.has_value() ? 1 : 0);
    if (item)
      value(*item);
  }
  template <class T, class U> void value(std::pair<T, U> &item) {
    (*this)(item.first, item.second);
  }
  void value(std::set<std::string> &items) {
    u32(static_cast<std::uint32_t>(items.size()));
    for (auto text : items)
      value(text);
  }
  void symbol(SymbolKind kind, std::uint32_t index) {
    if (!graph) {
      if (symbolFixups)
        symbolFixups->push_back({bytes.size(), kind, index, 4});
      u32(index);
      return;
    }
    if (!symbols->symbol)
      reject("missing logical symbol mapper");
    auto logical = symbols->symbol(kind, index);
    if (!logical || logical->empty())
      reject("unmapped exported symbol");
    value(*logical);
  }
  void function(int &index, SymbolKind kind = SymbolKind::Function) {
    if (index < -1)
      reject("invalid exported symbol reference");
    byte(index >= 0 ? 1 : 0);
    if (index >= 0)
      symbol(kind, static_cast<std::uint32_t>(index));
  }
  void closure(int &index) { function(index, SymbolKind::Closure); }
  void interface(std::uint32_t &index) { symbol(SymbolKind::Interface, index); }
  void package(std::uint32_t &index) {
    byte(index != unknownPackage ? 1 : 0);
    if (index != unknownPackage)
      symbol(SymbolKind::Package, index);
  }
};
struct Header {
  unsigned pointerBits = 0;
  std::uint32_t types = 0, regions = 0, universes = 0, binders = 0, roots = 0;
  bool indexed = false;
};
template <class T> std::size_t minimumValueBytes();
struct Reader : Fields<Reader> {
  std::span<const std::uint8_t> bytes;
  std::size_t offset = 0;
  const TypeGraphSymbols &symbols;
  const Header &header;
  std::span<const Type> types;
  std::span<const RegionId> regions;
  std::span<const RegionUniverse> universes;
  static constexpr auto symbolKinds =
      static_cast<std::size_t>(SymbolKind::Static) + 1;
  using ResolvedSymbols = std::array<std::vector<std::uint32_t>, symbolKinds>;
  std::array<std::vector<std::string_view>, symbolKinds> pendingSymbols;
  const ResolvedSymbols *resolvedSymbols = nullptr;
  std::array<std::size_t, symbolKinds> symbolOffsets{};
  Reader(std::span<const std::uint8_t> bytes, const TypeGraphSymbols &symbols,
         const Header &header)
      : bytes(bytes), symbols(symbols), header(header) {}
  std::size_t remaining() const { return bytes.size() - offset; }
  std::span<const std::uint8_t> block() {
    auto size = u32();
    if (size > remaining())
      reject("truncated indexed type record");
    auto result = bytes.subspan(offset, size);
    offset += size;
    return result;
  }
  std::uint8_t byte() {
    if (!remaining())
      reject("truncated type graph");
    return bytes[offset++];
  }
  std::uint32_t u32() {
    if (remaining() < 4)
      reject("truncated type graph integer");
    std::uint32_t n = 0;
    for (unsigned i = 0; i != 4; ++i)
      n |= static_cast<std::uint32_t>(byte()) << (8 * i);
    return n;
  }
  std::uint64_t u64() {
    if (remaining() < 8)
      reject("truncated type graph integer");
    std::uint64_t n = 0;
    for (unsigned i = 0; i != 8; ++i)
      n |= static_cast<std::uint64_t>(byte()) << (8 * i);
    return n;
  }
  bool flag() {
    auto n = byte();
    if (n > 1)
      reject("invalid type graph boolean");
    return n != 0;
  }
  template <class T> void value(T &n) {
    if constexpr (std::is_same_v<T, bool>)
      n = flag();
    else if constexpr (std::is_enum_v<T>) {
      auto tag = byte();
      if (tag > lastTag<T>())
        reject("invalid type graph semantic tag");
      n = static_cast<T>(tag);
    } else if constexpr (std::is_integral_v<T>) {
      auto bits = u64();
      if constexpr (std::is_signed_v<T>) {
        auto signedValue = std::bit_cast<std::int64_t>(bits);
        if (signedValue < std::numeric_limits<T>::min() ||
            signedValue > std::numeric_limits<T>::max())
          reject("type graph integer is not representable");
        n = static_cast<T>(signedValue);
      } else {
        if (bits > std::numeric_limits<T>::max())
          reject("type graph integer is not representable");
        n = static_cast<T>(bits);
      }
    } else
      record(*this, n);
  }
  void value(Type &type) {
    auto ref = u32();
    if (ref >= primitiveCount && ref - primitiveCount >= header.types)
      reject("dangling type graph reference");
    type = types[ref];
  }
  void value(RegionId &region) {
    auto ref = u32();
    if (ref >= 2 && ref - 2 >= header.regions)
      reject("dangling type graph region reference");
    region = regions[ref];
  }
  void universe(RegionUniverse &universe) {
    auto ref = u32();
    if (ref >= header.universes)
      reject("dangling type graph universe reference");
    universe = universes[ref];
  }
  void value(std::string &text) {
    auto count = u32();
    if (count > remaining())
      reject("truncated type graph string");
    text.assign(reinterpret_cast<const char *>(bytes.data() + offset), count);
    offset += count;
  }
  template <class T> void value(std::vector<T> &items) {
    auto count = u32();
    if (count > remaining() / minimumValueBytes<T>())
      reject("invalid type graph sequence length");
    items.clear();
    items.reserve(count);
    for (std::uint32_t i = 0; i < count; ++i) {
      T item{};
      value(item);
      items.push_back(std::move(item));
    }
  }
  template <class T> void value(std::optional<T> &item) {
    if (flag()) {
      T temporary{};
      value(temporary);
      item = std::move(temporary);
    } else
      item.reset();
  }
  template <class T, class U> void value(std::pair<T, U> &item) {
    (*this)(item.first, item.second);
  }
  void value(std::set<std::string> &items) {
    auto count = u32();
    if (count > remaining() / 4)
      reject("invalid type graph feature count");
    for (std::uint32_t i = 0; i < count; ++i) {
      std::string text;
      value(text);
      if (!items.insert(std::move(text)).second)
        reject("duplicate type graph target feature");
    }
  }
  std::uint32_t symbol(SymbolKind kind) {
    const auto count = u32();
    if (count > remaining())
      reject("truncated type graph symbol");
    const std::string_view logical(
        reinterpret_cast<const char *>(bytes.data() + offset), count);
    offset += count;
    if (logical.empty() || (!resolvedSymbols && !symbols.resolve))
      reject("missing logical symbol resolver");
    const auto table = static_cast<std::size_t>(kind);
    if (resolvedSymbols)
      return resolvedSymbols->at(table).at(symbolOffsets[table]++);
    auto &pending = pendingSymbols[table];
    const auto index = static_cast<std::uint32_t>(pending.size());
    pending.push_back(logical);
    return index;
  }
  ResolvedSymbols resolveSymbols() const {
    ResolvedSymbols result;
    for (std::size_t i = 0; i < symbolKinds; ++i) {
      const auto kind = static_cast<SymbolKind>(i);
      std::unordered_map<std::string_view, std::uint32_t> resolved;
      result[i].reserve(pendingSymbols[i].size());
      for (auto name : pendingSymbols[i]) {
        if (auto found = resolved.find(name); found != resolved.end()) {
          result[i].push_back(found->second);
          continue;
        }
        const auto index = symbols.resolve(kind, name);
        if (!index)
          reject("unresolved imported symbol: " + std::string(name));
        if ((kind == SymbolKind::Function || kind == SymbolKind::Closure) &&
            *index >
                static_cast<std::uint32_t>(std::numeric_limits<int>::max()))
          reject("imported symbol index is not representable");
        if (kind == SymbolKind::Package && *index == unknownPackage)
          reject("resolved package has invalid identity");
        result[i].push_back(*index);
        resolved.emplace(name, *index);
      }
    }
    return result;
  }
  void function(int &index, SymbolKind kind = SymbolKind::Function) {
    if (!flag()) {
      index = -1;
      return;
    }
    auto resolved = symbol(kind);
    if (resolved > static_cast<unsigned>(std::numeric_limits<int>::max()))
      reject("imported symbol index is not representable");
    index = static_cast<int>(resolved);
  }
  void closure(int &index) { function(index, SymbolKind::Closure); }
  void interface(std::uint32_t &index) {
    index = symbol(SymbolKind::Interface);
  }
  void package(std::uint32_t &index) {
    if (!flag())
      index = unknownPackage;
    else {
      index = symbol(SymbolKind::Package);
      if (index == unknownPackage)
        reject("resolved package has invalid identity");
    }
  }
};
using CompactProduct = BasicImportedProduct<BorrowedTypeStorage>;
using CompactPointer = BasicImportedPointer<BorrowedTypeStorage>;
using CompactParameter = BasicTypeParameter<BorrowedTypeStorage>;
using CompactCallable = BasicCallableType<BorrowedTypeStorage>;
using CompactView = BasicViewType<BorrowedTypeStorage>;
using CompactSlice = BasicSliceType<BorrowedTypeStorage>;
using CompactErased = BasicErasedType<BorrowedTypeStorage>;
using CompactDefinition =
    std::variant<CompactProduct, CompactView, CompactPointer, CompactSlice,
                 CompactParameter, CompactCallable, CompactErased>;
using CompactDefinitionView =
    std::variant<CompactProduct *, CompactView *, CompactPointer *,
                 CompactSlice *, CompactParameter *, CompactCallable *,
                 CompactErased *>;

class CompactArena {
public:
  ~CompactArena() { reset(); }
  void reset() {
    for (auto &destroy : destructors)
      destroy();
    destructors.clear();
    memory.release();
  }
  template <class T> std::span<T> allocate(std::size_t count) {
    static_assert(std::is_nothrow_default_constructible_v<T>);
    if (!count)
      return {};
    std::pmr::polymorphic_allocator<T> allocator(&memory);
    auto *items = allocator.allocate(count);
    if constexpr (!std::is_trivially_destructible_v<T>)
      destructors.emplace_back(
          [items, count] { std::destroy_n(items, count); });
    std::uninitialized_value_construct_n(items, count);
    return {items, count};
  }

private:
  std::array<std::byte, 4096> buffer;
  std::pmr::monotonic_buffer_resource memory{buffer.data(), buffer.size()};
  std::vector<std::function<void()>> destructors;
};

struct CompactReader : Reader {
  using Reader::value;
  std::shared_ptr<CompactArena> arena;
  CompactReader(std::span<const std::uint8_t> bytes,
                const TypeGraphSymbols &symbols, const Header &header,
                std::shared_ptr<CompactArena> arena = {})
      : Reader(bytes, symbols, header),
        arena(arena ? std::move(arena) : std::make_shared<CompactArena>()) {}
  template <class... T> void operator()(T &...values) { (value(values), ...); }
  template <class T> void value(T &item) {
    if constexpr (std::is_arithmetic_v<T> || std::is_enum_v<T>)
      Reader::value(item);
    else
      record(*this, item);
  }
  void value(std::string_view &text) {
    const auto count = u32();
    if (count > remaining())
      reject("truncated type graph string");
    text = {reinterpret_cast<const char *>(bytes.data() + offset), count};
    offset += count;
  }
  template <class T> void value(std::span<T> &items) {
    const auto count = u32();
    if (count > remaining() / minimumValueBytes<T>())
      reject("invalid type graph sequence length");
    auto decoded = arena->allocate<T>(count);
    for (auto &item : decoded)
      value(item);
    items = decoded;
  }
  template <class T> void value(BorrowedTypeSequence<T> &items) {
    std::span<T> decoded;
    value(decoded);
    items = decoded;
  }
  template <class T> void value(std::optional<T> &item) {
    if (flag()) {
      item.emplace();
      value(*item);
    } else
      item.reset();
  }
  template <class T, class U> void value(std::pair<T, U> &item) {
    (*this)(item.first, item.second);
  }
  template <class T> void name(T &item) { value(item); }
  template <class T> void names(T &items) { value(items); }
  void features(BorrowedTypeSequence<std::string_view> &items) {
    value(items);
    std::set<std::string_view> unique;
    for (auto feature : items)
      if (!unique.insert(feature).second)
        reject("duplicate type graph target feature");
  }
};

ImportedTypeDefinition definitionFor(ImportedTypeKind kind) {
  switch (kind) {
  case ImportedTypeKind::Product:
    return ImportedProduct{};
  case ImportedTypeKind::View:
    return ViewType{};
  case ImportedTypeKind::Pointer:
    return ImportedPointer{};
  case ImportedTypeKind::Slice:
    return SliceType{};
  case ImportedTypeKind::Parameter:
    return TypeParameter{};
  case ImportedTypeKind::Callable:
    return CallableType{};
  case ImportedTypeKind::Erased:
    return ErasedType{};
  }
  reject("invalid imported type kind");
}
CompactDefinition compactDefinitionFor(ImportedTypeKind kind) {
  switch (kind) {
  case ImportedTypeKind::Product:
    return CompactProduct{};
  case ImportedTypeKind::View:
    return CompactView{};
  case ImportedTypeKind::Pointer:
    return CompactPointer{};
  case ImportedTypeKind::Slice:
    return CompactSlice{};
  case ImportedTypeKind::Parameter:
    return CompactParameter{};
  case ImportedTypeKind::Callable:
    return CompactCallable{};
  case ImportedTypeKind::Erased:
    return CompactErased{};
  }
  reject("invalid imported type kind");
}
template <class T> T ownCompact(const T &value) { return value; }
std::string ownCompact(std::string_view value) { return std::string(value); }
template <class T> auto ownCompact(BorrowedTypeSequence<T> values);
template <class Storage>
CallableParameter ownCompact(const BasicCallableParameter<Storage> &value) {
  return {value.type, value.mode, ownCompact(value.name)};
}
template <class Storage>
CallableType ownCompact(const BasicCallableType<Storage> &value) {
  CallableType result;
  result.parameters = ownCompact(value.parameters);
  result.result = value.result;
  result.error = value.error;
  result.abiResult = value.abiResult;
  result.resultSources = ownCompact(value.resultSources);
  result.mode = value.mode;
  result.regions = ownCompact(value.regions);
  result.environment = value.environment;
  result.function = value.function;
  result.name = value.name;
  result.regionParameters = ownCompact(value.regionParameters);
  result.parameterRegions = ownCompact(value.parameterRegions);
  result.regionUniverse = value.regionUniverse;
  result.regionRequirements = ownCompact(value.regionRequirements);
  result.resultFromEnvironment = value.resultFromEnvironment;
  result.environmentMode = value.environmentMode;
  result.unsafeCall = value.unsafeCall;
  result.abi = value.abi;
  result.variadic = value.variadic;
  result.targetFeatures.insert(value.targetFeatures.begin(),
                               value.targetFeatures.end());
  return result;
}
template <class Storage>
TypeField ownCompact(const BasicTypeField<Storage> &value) {
  return {ownCompact(value.name), value.type};
}
template <class Storage>
VariantType ownCompact(const BasicVariantType<Storage> &value) {
  return {ownCompact(value.name), ownCompact(value.fields)};
}
template <class T> auto ownCompact(BorrowedTypeSequence<T> values) {
  std::vector<decltype(ownCompact(std::declval<const T &>()))> result;
  result.reserve(values.size());
  for (const auto &value : values)
    result.push_back(ownCompact(value));
  return result;
}
ProductLayout ownCompact(const BasicProductLayout<BorrowedTypeStorage> &value) {
  return {value.kind,
          value.alignment,
          value.packing,
          value.unionType,
          value.tag,
          ownCompact(value.pinnedFields),
          ownCompact(value.discriminants),
          value.unpin,
          ownCompact(value.unpinConditions),
          value.conditionalUnpin};
}
ProductType ownCompact(const BasicProductType<BorrowedTypeStorage> &value) {
  return {ownCompact(value.name),
          ownCompact(value.fields),
          value.copyRequested,
          value.conditionalCopy,
          ownCompact(value.copyConditions),
          value.hasDestructor,
          value.destructor,
          value.kind,
          ownCompact(value.variants),
          ownCompact(value.components),
          value.callable,
          ownCompact(value.genericParameters),
          value.genericOrigin,
          ownCompact(value.genericArguments),
          value.arrayCount,
          ownCompact(value.opaqueBounds),
          value.package,
          value.regionOrigin,
          ownCompact(value.regionArguments),
          value.regionPattern,
          ownCompact(value.layout),
          value.nativeCleanup,
          value.vector,
          value.normalizedFields};
}
ImportedProduct ownCompact(const CompactProduct &value) {
  ImportedProduct result{
      ownCompact(value.descriptor), {}, ownCompact(value.coroutineInterior)};
  if (value.closure)
    result.closure = ownCompact(*value.closure);
  return result;
}
ViewType ownCompact(const CompactView &value) {
  return {value.payload, value.mode, ownCompact(value.name), value.region};
}
ImportedPointer ownCompact(const CompactPointer &value) {
  return {ownCompact(value.descriptor)};
}
SliceType ownCompact(const CompactSlice &value) {
  return {value.element, ownCompact(value.name), value.metadata};
}
TypeParameter ownCompact(const CompactParameter &value) {
  return {ownCompact(value.name),
          value.copyRequested,
          value.sized,
          value.kind,
          value.valueType,
          value.value,
          ownCompact(value.operation),
          ownCompact(value.operands),
          value.callableConstraint,
          ownCompact(value.callableLocalParameters),
          ownCompact(value.regionArguments),
          value.unpin,
          value.thin,
          value.numeric,
          value.erasedCallableConstraint};
}
ErasedType ownCompact(const CompactErased &value) {
  return {ownCompact(value.name),
          value.declaration,
          ownCompact(value.arguments),
          ownCompact(value.associated),
          ownCompact(value.methods),
          ownCompact(value.methodTypes),
          ownCompact(value.methodOwners),
          ownCompact(value.methodSlots),
          ownCompact(value.parentInterfaces),
          ownCompact(value.regionArguments),
          ownCompact(value.regionParameters),
          value.regionUniverse,
          ownCompact(value.regionRequirements),
          value.bound};
}
struct MinimumRecordSize : Fields<MinimumRecordSize> {
  std::size_t bytes = 0;
  template <class T> void value(T &value) {
    if constexpr (std::is_same_v<T, bool> || std::is_enum_v<T>)
      ++bytes;
    else if constexpr (std::is_integral_v<T>)
      bytes += 8;
    else
      record(*this, value);
  }
  void value(Type &) { bytes += 4; }
  void value(RegionId &) { bytes += 4; }
  void value(std::string &) { bytes += 4; }
  void value(std::string_view &) { bytes += 4; }
  template <class T> void value(std::vector<T> &) { bytes += 4; }
  template <class T> void value(std::span<T> &) { bytes += 4; }
  template <class T> void value(BorrowedTypeSequence<T> &) { bytes += 4; }
  template <class T> void value(std::optional<T> &) { ++bytes; }
  template <class T, class U> void value(std::pair<T, U> &value) {
    (*this)(value.first, value.second);
  }
  void value(std::set<std::string> &) { bytes += 4; }
  void function(int &) { ++bytes; }
  void closure(int &) { ++bytes; }
  void interface(std::uint32_t &) { bytes += 4; }
  void package(std::uint32_t &) { ++bytes; }
  void universe(RegionUniverse &) { bytes += 4; }
};

template <class T> std::size_t minimumValueBytes() {
  static const auto bytes = [] {
    T value{};
    MinimumRecordSize size;
    size.value(value);
    return size.bytes;
  }();
  return bytes;
}

std::size_t minimumDefinitionBytes(ImportedTypeKind kind) {
  static const auto sizes = [] {
    std::array<std::size_t,
               static_cast<std::size_t>(ImportedTypeKind::Erased) + 1>
        result{};
    for (std::size_t i = 0; i < result.size(); ++i) {
      auto definition = definitionFor(static_cast<ImportedTypeKind>(i));
      MinimumRecordSize size;
      std::visit([&](auto &value) { record(size, value); }, definition);
      result[i] = size.bytes + 1;
    }
    return result;
  }();
  return sizes[static_cast<std::size_t>(kind)];
}
template <class T>
const T *definitionRecord(const ImportedTypeDefinition &definition) {
  return std::get_if<T>(&definition);
}
template <class T>
auto definitionRecord(const ImportedTypeDefinitionView &definition) {
  if constexpr (std::is_same_v<T, ImportedProduct>)
    return std::get_if<ImportedProductView>(&definition);
  else if constexpr (std::is_same_v<T, ImportedPointer>)
    return std::get_if<ImportedPointerView>(&definition);
  else {
    auto record = std::get_if<const T *>(&definition);
    return record ? *record : nullptr;
  }
}
template <class T, class Definition>
auto compactRecord(const Definition &definition) {
  using Record = std::conditional_t<
      std::is_same_v<T, ImportedProduct>, CompactProduct,
      std::conditional_t<
          std::is_same_v<T, ImportedPointer>, CompactPointer,
          std::conditional_t<
              std::is_same_v<T, TypeParameter>, CompactParameter,
              std::conditional_t<
                  std::is_same_v<T, CallableType>, CompactCallable,
                  std::conditional_t<
                      std::is_same_v<T, ErasedType>, CompactErased,
                      std::conditional_t<std::is_same_v<T, ViewType>,
                                         CompactView, CompactSlice>>>>>>;
  if constexpr (std::is_same_v<Definition, CompactDefinition>)
    return std::get_if<Record>(&definition);
  else {
    auto found = std::get_if<Record *>(&definition);
    return found ? *found : nullptr;
  }
}
template <class T> auto definitionRecord(const CompactDefinition &definition) {
  return compactRecord<T>(definition);
}
template <class T>
auto definitionRecord(const CompactDefinitionView &definition) {
  return compactRecord<T>(definition);
}
template <class Visitor>
decltype(auto) visitDefinition(Visitor &&visitor,
                               const ImportedTypeDefinition &definition) {
  return std::visit(std::forward<Visitor>(visitor), definition);
}
template <class Visitor>
decltype(auto) visitDefinition(Visitor &&visitor,
                               const CompactDefinition &definition) {
  return std::visit(std::forward<Visitor>(visitor), definition);
}
template <class Visitor>
decltype(auto) visitDefinition(Visitor &&visitor,
                               const CompactDefinitionView &definition) {
  return std::visit(
      [&](auto record) -> decltype(auto) { return visitor(*record); },
      definition);
}
template <class Visitor>
decltype(auto) visitDefinition(Visitor &&visitor,
                               const ImportedTypeDefinitionView &definition) {
  return std::visit(
      [&](const auto &record) -> decltype(auto) {
        if constexpr (std::is_pointer_v<std::decay_t<decltype(record)>>)
          return visitor(*record);
        else
          return visitor(record);
      },
      definition);
}
class DecodedDefinitions {
public:
  DecodedDefinitions(const TypeStore &store, std::span<const Type> ids)
      : store(store), ids(ids) {}
  std::size_t size() const { return ids.size(); }
  ImportedTypeDefinitionView operator[](std::size_t index) const {
    return store.importedDefinitionView(ids[index]);
  }

private:
  const TypeStore &store;
  std::span<const Type> ids;
};
class CompactDefinitions {
public:
  CompactDefinitions(const std::vector<CompactDefinitionView> &dense)
      : dense(dense) {}
  CompactDefinitions(
      const std::unordered_map<std::size_t, CompactDefinitionView> &sparse,
      std::span<const ImportedTypeKind> kinds)
      : sparse(&sparse), kinds(kinds) {}
  std::size_t size() const { return sparse ? kinds.size() : dense.size(); }
  CompactDefinitionView operator[](std::size_t index) const {
    if (!sparse)
      return dense[index];
    if (auto found = sparse->find(index); found != sparse->end())
      return found->second;
    return std::visit(
        [](auto &&record) -> CompactDefinitionView {
          return static_cast<std::decay_t<decltype(record)> *>(nullptr);
        },
        compactDefinitionFor(kinds[index]));
  }

private:
  std::span<const CompactDefinitionView> dense;
  const std::unordered_map<std::size_t, CompactDefinitionView> *sparse =
      nullptr;
  std::span<const ImportedTypeKind> kinds;
};
class CompactTypes {
public:
  const RegionStore &regionStore;
  unsigned pointerBits;
  VaListAbi abi;
  CompactDefinitions definitions;
  std::function<void(Type)> demand{};
  void requireDefinition(Type type) const {
    if (demand)
      demand(type);
  }
  bool contains(Type type) const {
    return type != Type::Unknown &&
           type.index() < builtinTypeCount + definitions.size();
  }
  bool isProduct(Type type) const { return holds<CompactProduct>(type); }
  bool isView(Type type) const { return holds<CompactView>(type); }
  bool isPointer(Type type) const { return holds<CompactPointer>(type); }
  bool isSlice(Type type) const { return holds<CompactSlice>(type); }
  bool isErased(Type type) const { return holds<CompactErased>(type); }
  bool isFunctionPointer(Type type) const {
    return holds<CompactCallable>(type);
  }
  bool isParameter(Type type) const {
    return holds<CompactParameter>(type) &&
           (parameter(type).kind == TypeParameterKind::Type ||
            (parameter(type).kind == TypeParameterKind::Projection &&
             parameter(type).valueType == Type::Unknown));
  }
  bool isConstant(Type type) const {
    return holds<CompactParameter>(type) && !isParameter(type);
  }
  const BasicProductType<BorrowedTypeStorage> &product(Type type) const {
    return get<CompactProduct>(type).descriptor;
  }
  const CompactParameter &parameter(Type type) const {
    return get<CompactParameter>(type);
  }
  const CompactView &view(Type type) const { return get<CompactView>(type); }
  const CompactView &pointer(Type type) const {
    return get<CompactPointer>(type).descriptor;
  }
  const CompactSlice &slice(Type type) const { return get<CompactSlice>(type); }
  bool isCallable(Type type) const {
    return isFunctionPointer(type) ||
           (isParameter(type) &&
            parameter(type).callableConstraint != Type::Unknown) ||
           (isProduct(type) && get<CompactProduct>(type).closure.has_value());
  }
  const CompactCallable &callable(Type type) const {
    if (isParameter(type))
      return callable(parameter(type).callableConstraint);
    if (isProduct(type))
      return *get<CompactProduct>(type).closure;
    return get<CompactCallable>(type);
  }
  std::optional<NumericLiteral> scalarConstantValue(Type type) const {
    if (isConstant(type) && parameter(type).kind == TypeParameterKind::Value)
      return parameter(type).numeric;
    return std::nullopt;
  }
  unsigned targetPointerBits() const { return pointerBits; }
  VaListAbi vaListAbi() const { return abi; }
  const RegionStore &regions() const { return regionStore; }
  std::string_view name(Type type) const {
    if (type.index() < builtinTypeCount)
      return typeName(type);
    requireDefinition(type);
    return std::visit(
        [](const auto *record) -> std::string_view {
          if constexpr (requires { record->descriptor; })
            return record->descriptor.name;
          else
            return record->name;
        },
        definitions[type.index() - builtinTypeCount]);
  }

private:
  template <class T> bool holds(Type type) const {
    return type.index() >= builtinTypeCount && contains(type) &&
           std::holds_alternative<T *>(
               definitions[type.index() - builtinTypeCount]);
  }
  template <class T> const T &get(Type type) const {
    requireDefinition(type);
    return *std::get<T *>(definitions[type.index() - builtinTypeCount]);
  }
};
template <class Definition> bool nominal(const Definition &definition) {
  if (auto product = definitionRecord<ImportedProduct>(definition)) {
    const auto &r = product->descriptor;
    return r.genericOrigin == Type::Unknown &&
           r.regionOrigin == Type::Unknown &&
           (r.kind == AggregateKind::Product ||
            r.kind == AggregateKind::Enumeration ||
            r.kind == AggregateKind::Opaque ||
            r.kind == AggregateKind::NativeVector);
  }
  if (auto parameter = definitionRecord<TypeParameter>(definition))
    return parameter->kind == TypeParameterKind::Type ||
           parameter->kind == TypeParameterKind::Constant;
  return false;
}
void validIdentity(const DefinitionIdentity &id, bool parameter) {
  if (id.package.empty() || id.definition.empty() ||
      id.parameterOrdinal.has_value() != parameter)
    reject("invalid logical definition identity");
}
struct WireRegion {
  RegionKind kind = RegionKind::Unspecified;
  std::uint32_t binder = 0, universe = 0;
  std::string name;
  std::vector<std::uint32_t> sources;
};
template <class A> void record(A &a, WireRegion &r) {
  a(r.kind);
  if constexpr (std::is_same_v<A, Writer>) {
    a.u32(r.binder);
    a.u32(r.universe);
    a(r.name);
    a.u32(static_cast<std::uint32_t>(r.sources.size()));
    for (auto ref : r.sources)
      a.u32(ref);
  } else {
    r.binder = a.u32();
    r.universe = a.u32();
    a(r.name);
    auto count = a.u32();
    if (count > a.remaining() / 4)
      reject("invalid intersection source count");
    for (std::uint32_t i = 0; i < count; ++i) {
      auto ref = a.u32();
      if (ref >= 2 && ref - 2 >= a.header.regions)
        reject("dangling intersection source");
      r.sources.push_back(ref);
    }
    if (r.kind < RegionKind::Bound ||
        (r.kind != RegionKind::Intersection &&
         (r.binder >= a.header.binders || r.universe >= a.header.universes ||
          count)) ||
        (r.kind == RegionKind::Intersection &&
         (r.binder || r.universe || count < 2)))
      reject("invalid region graph record");
  }
}
constexpr std::array<std::uint8_t, 8> magic{'M', 'T', 'T', 'Y',
                                            'R', 'E', 'G', 0};
constexpr std::uint32_t version = 3;
constexpr std::uint32_t indexedVersion = 6;
void readHeader(Reader &reader, Header &header, unsigned pointerBits) {
  if (reader.bytes.size() > limits::sourceBytes)
    reject("type graph exceeds source byte limit");
  for (auto expected : magic)
    if (reader.byte() != expected)
      reject("invalid type graph magic");
  auto revision = reader.u32();
  if (revision != version && revision != indexedVersion)
    reject("incompatible type graph version");
  header.indexed = revision == indexedVersion;
  header.pointerBits = reader.u32();
  if (header.pointerBits != pointerBits)
    reject("incompatible type graph target pointer width");
  if (pointerBits != 16 && pointerBits != 32 && pointerBits != 64)
    reject("invalid type graph target pointer width");
  header.types = reader.u32();
  header.regions = reader.u32();
  header.universes = reader.u32();
  header.binders = reader.u32();
  header.roots = reader.u32();
  if (!header.universes || header.types > limits::products ||
      header.types > reader.remaining() ||
      header.regions > reader.remaining() ||
      header.universes > reader.remaining() / 4 ||
      header.binders > reader.remaining() / 4 ||
      header.roots > reader.remaining() / 4)
    reject("invalid type graph table count");
}
struct Tables {
  std::vector<ImportedTypeKind> kinds;
  std::vector<std::uint32_t> parents, binders;
  std::vector<WireRegion> regions;
};
void readTables(Reader &reader, Tables &tables) {
  for (std::uint32_t i = 0; i < reader.header.types; ++i) {
    ImportedTypeKind kind{};
    reader(kind);
    tables.kinds.push_back(kind);
  }
  for (std::uint32_t i = 0; i < reader.header.universes; ++i) {
    auto parent = reader.u32();
    if (i ? parent >= i : parent != 0)
      reject("cyclic or dangling region universe ancestry");
    tables.parents.push_back(parent);
  }
  for (std::uint32_t i = 0; i < reader.header.binders; ++i) {
    auto universe = reader.u32();
    if (universe >= reader.header.universes)
      reject("dangling region binder universe");
    tables.binders.push_back(universe);
  }
  for (std::uint32_t i = 0; i < reader.header.regions; ++i) {
    WireRegion region;
    record(reader, region);
    tables.regions.push_back(std::move(region));
  }
}
std::vector<Type> builtinTypes() {
  return {primitiveTypes.begin(), primitiveTypes.end()};
}
void importRegions(TypeStore &candidate, const Tables &tables,
                   std::vector<RegionId> &regions,
                   std::vector<RegionUniverse> &universes) {
  auto &store = candidate.regions();
  universes.push_back(0);
  for (std::size_t i = 1; i < tables.parents.size(); ++i)
    universes.push_back(
        store.binder(universes[tables.parents[i]], true).universe);
  std::vector<RegionScope> binders;
  for (auto universe : tables.binders)
    binders.push_back(store.binder(universes[universe]));
  regions.resize(2 + tables.regions.size());
  regions[0] = RegionId::Unspecified;
  regions[1] = RegionId::Static;
  for (std::size_t i = 0; i < tables.regions.size(); ++i) {
    const auto &r = tables.regions[i];
    if (r.kind == RegionKind::Intersection)
      continue;
    if (r.universe != tables.binders[r.binder])
      reject("region and binder universes disagree");
    auto scope = binders[r.binder];
    switch (r.kind) {
    case RegionKind::Bound:
      regions[i + 2] = store.bound(scope, r.name);
      break;
    case RegionKind::Rigid:
      regions[i + 2] = store.rigid(scope, r.name);
      break;
    case RegionKind::Inference:
      if (!r.name.empty())
        reject("named inference region");
      regions[i + 2] = store.inference(scope);
      break;
    case RegionKind::Local:
      if (!r.name.empty())
        reject("named local region");
      regions[i + 2] = store.local(scope);
      break;
    default:
      reject("invalid imported region kind");
    }
  }
  for (std::size_t i = 0; i < tables.regions.size(); ++i) {
    const auto &r = tables.regions[i];
    if (r.kind != RegionKind::Intersection)
      continue;
    if (!r.name.empty())
      reject("named region intersection");
    std::set<std::uint32_t> seen;
    std::vector<RegionId> sources;
    for (auto ref : r.sources) {
      if (ref < 2 || tables.regions[ref - 2].kind == RegionKind::Intersection ||
          !seen.insert(ref).second)
        reject("cyclic or noncanonical region intersection");
      sources.push_back(regions[ref]);
    }
    regions[i + 2] = store.intersection(std::move(sources));
  }
}
template <class Derived> struct SemanticWalk : Fields<Derived> {
  template <class T> void value(T &item) {
    if constexpr (!std::is_arithmetic_v<T> && !std::is_enum_v<T>)
      record(*static_cast<Derived *>(this), item);
  }
  void value(std::string &) {}
  void value(std::string_view &) {}
  void value(std::set<std::string> &) {}
  void value(RegionId &) {}
  void universe(RegionUniverse &) {}
  void function(int &) {}
  void closure(int &) {}
  void interface(std::uint32_t &) {}
  void package(std::uint32_t &) {}
  template <class T> void value(std::vector<T> &items) {
    for (auto &item : items)
      static_cast<Derived *>(this)->value(item);
  }
  template <class T> void value(std::span<T> &items) {
    for (auto &item : items)
      static_cast<Derived *>(this)->value(item);
  }
  template <class T> void value(std::optional<T> &item) {
    if (item)
      static_cast<Derived *>(this)->value(*item);
  }
  template <class T, class U> void value(std::pair<T, U> &item) {
    (*static_cast<Derived *>(this))(item.first, item.second);
  }
};
template <class Edges>
std::vector<std::size_t> acyclic(const Edges &edges, bool probe = false) {
  std::vector<unsigned char> state(edges.size());
  std::vector<unsigned> depths(edges.size(), 1);
  std::vector<std::size_t> order;
  struct Frame {
    std::size_t node, next = 0;
  };
  std::vector<Frame> stack;
  for (std::size_t root = 0; root < edges.size(); ++root) {
    if (state[root])
      continue;
    state[root] = 1;
    stack.push_back({root});
    while (!stack.empty()) {
      auto &frame = stack.back();
      if (frame.next == edges[frame.node].size()) {
        for (auto child : edges[frame.node])
          depths[frame.node] = std::max(depths[frame.node], depths[child] + 1);
        if (depths[frame.node] > limits::typeDepth) {
          if (probe)
            return {};
          reject("imported type nesting exceeds compiler depth limit");
        }
        state[frame.node] = 2;
        order.push_back(frame.node);
        stack.pop_back();
      } else {
        auto next = edges[frame.node][frame.next++];
        if (state[next] == 1) {
          if (probe)
            return {};
          reject("cyclic type graph");
        }
        if (!state[next]) {
          if (stack.size() >= limits::typeDepth) {
            if (probe)
              return {};
            reject("imported type nesting exceeds compiler depth limit");
          }
          state[next] = 1;
          stack.push_back({next});
        }
      }
    }
  }
  return order;
}
std::size_t graphIndex(std::span<const Type> ids, Type type) {
  if (ids.empty() || type.index() < ids.front().index())
    reject("type reference is outside the decoded graph");
  auto index = static_cast<std::size_t>(type.index() - ids.front().index());
  if (index >= ids.size() || ids[index] != type)
    reject("type reference is outside the decoded graph");
  return index;
}
template <class Store, class Callable>
void validateCallable(const Store &store, const Callable &r, bool pointer) {
  if (pointer && (r.environment != Type::Unknown || r.function != -1))
    reject("function pointer has a closure environment or function identity");
  if (pointer && (r.result == Type::Unknown || r.abiResult == Type::Unknown))
    reject("unresolved function pointer result");
  if (!r.parameterRegions.empty() &&
      r.parameterRegions.size() != r.parameters.size())
    reject("callable region arity mismatch");
  for (auto source : r.resultSources)
    if (source >= r.parameters.size())
      reject("dangling callable result source");
  std::set<RegionId> parameters;
  for (auto region : r.regionParameters) {
    const auto &record = store.regions().get(region);
    if (record.kind != RegionKind::Bound ||
        !store.regions().ancestor(record.universe, r.regionUniverse) ||
        !parameters.insert(region).second)
      reject("invalid callable region parameter");
  }
  for (const auto &parameter : r.parameters)
    if (parameter.type == Type::Unknown || store.isConstant(parameter.type))
      reject("invalid callable parameter type");
}
struct TypeGraphProof {
  std::uint64_t expanded = 1, elements = 1;
  bool drops = false;
};
template <class Store, class Definitions>
void validateGraph(
    const Store &store, std::span<const Type> ids,
    const Definitions &definitions,
    std::vector<std::size_t> *selected = nullptr,
    std::unordered_map<std::size_t, TypeGraphProof> *proofs = nullptr) {
  auto count = selected ? 0 : ids.size();
  std::vector<std::vector<std::size_t>> valueEdges(count), originEdges(count),
      interfaceEdges(count);
  std::unordered_map<std::size_t, std::size_t> positions;
  std::vector<std::size_t> ordinals;
  auto position = [&](std::size_t index) {
    if (!selected)
      return index;
    auto [found, added] = positions.emplace(index, ordinals.size());
    if (added) {
      ordinals.push_back(index);
      valueEdges.emplace_back();
      originEdges.emplace_back();
      interfaceEdges.emplace_back();
    }
    return found->second;
  };
  auto node = [&](Type type) {
    if constexpr (requires { store.requireDefinition(type); })
      store.requireDefinition(type);
    return position(graphIndex(ids, type));
  };
  auto edge = [&](auto &edges, std::size_t from, Type type) {
    auto target = node(type);
    edges[from].push_back(target);
  };
  auto validType = [&](Type type) {
    return type != Type::Unknown && !store.isConstant(type);
  };
  auto scalar = [](Type type) {
    return isInteger(type) || type == Type::Bool || type == Type::Char;
  };
  for (std::size_t next = 0;
       next < (selected ? selected->size() : definitions.size()); ++next) {
    auto i = selected ? (*selected)[next] : next;
    auto slot = position(i);
    const auto &definition = definitions[i];
    if (auto imported = definitionRecord<ImportedProduct>(definition)) {
      const auto &r = imported->descriptor;
      if (r.hasDestructor != (r.destructor >= 0))
        reject("inconsistent product destructor");
      if ((r.nativeCleanup == NativeCleanup::RefRelease &&
           r.kind != AggregateKind::Ref) ||
          (r.nativeCleanup == NativeCleanup::RefMutRelease &&
           r.kind != AggregateKind::RefMut) ||
          (r.nativeCleanup == NativeCleanup::VaListEnd &&
           r.kind != AggregateKind::VarArgs))
        reject("native cleanup does not match product representation");
      if (!isInteger(r.layout.tag) || r.layout.unpin < -1 ||
          r.layout.unpin > 1 ||
          (r.layout.alignment && !std::has_single_bit(r.layout.alignment)) ||
          (r.layout.packing && !std::has_single_bit(r.layout.packing)))
        reject("invalid product layout");
      if (r.genericOrigin != Type::Unknown &&
          (!store.isProduct(r.genericOrigin) ||
           store.product(r.genericOrigin).genericParameters.size() !=
               r.genericArguments.size()))
        reject("invalid generic product origin or arity");
      if (r.genericOrigin != Type::Unknown) {
        const auto &parameters =
            store.product(r.genericOrigin).genericParameters;
        for (std::size_t p = 0; p < parameters.size(); ++p) {
          auto parameter = parameters[p];
          if ((!store.isParameter(parameter) && !store.isConstant(parameter)) ||
              (store.parameter(parameter).kind != TypeParameterKind::Type &&
               store.parameter(parameter).kind != TypeParameterKind::Constant))
            reject("invalid generic product origin parameter");
          auto argument = r.genericArguments[p];
          if (store.parameter(parameter).kind == TypeParameterKind::Type) {
            if (!validType(argument))
              reject("invalid generic product type argument");
          } else {
            if (!store.isConstant(argument))
              reject("generic product constant argument is not constant");
            if (store.parameter(argument).valueType !=
                store.parameter(parameter).valueType)
              reject("generic product constant argument type mismatch");
          }
        }
      }
      if ((r.regionOrigin != Type::Unknown &&
           !store.isProduct(r.regionOrigin)) ||
          (r.regionPattern != Type::Unknown &&
           !store.isProduct(r.regionPattern)) ||
          (r.normalizedFields && r.regionOrigin == Type::Unknown))
        reject("invalid regional product origin");
      for (auto origin : {r.genericOrigin, r.regionOrigin})
        if (origin != Type::Unknown) {
          if (store.product(origin).kind != r.kind)
            reject("product origin representation mismatch");
          edge(originEdges, slot, origin);
        }
      std::set<Type> parameters;
      for (auto parameter : r.genericParameters) {
        if ((!store.isParameter(parameter) && !store.isConstant(parameter)) ||
            !parameters.insert(parameter).second)
          reject("invalid generic parameter list");
        auto kind = store.parameter(parameter).kind;
        if (kind != TypeParameterKind::Type &&
            kind != TypeParameterKind::Constant)
          reject("generic list contains a non-definition parameter");
        if (kind == TypeParameterKind::Constant &&
            !scalar(store.parameter(parameter).valueType))
          reject("generic const parameter requires a supported scalar type");
      }
      for (const auto &field : r.fields) {
        if (!validType(field.type))
          reject("invalid product field type");
        if (store.isProduct(field.type) || store.isSlice(field.type))
          edge(valueEdges, slot, field.type);
      }
      for (auto pinned : r.layout.pinnedFields)
        if (pinned >= r.fields.size())
          reject("dangling pinned field");
      for (auto [parameter, condition] : r.layout.unpinConditions)
        if (parameter >= (r.genericOrigin == Type::Unknown
                              ? r.genericParameters.size()
                              : store.product(r.genericOrigin)
                                    .genericParameters.size()) ||
            condition > 7)
          reject("invalid conditional Unpin parameter");
      for (const auto &variant : r.variants)
        for (auto field : variant.fields)
          if (field >= r.fields.size())
            reject("dangling enumeration field");
      if (!r.layout.discriminants.empty() &&
          r.layout.discriminants.size() != r.variants.size())
        reject("enumeration discriminant arity mismatch");
      for (const auto &literal : r.layout.discriminants)
        if (!integerLiteralFits(literal, r.layout.tag,
                                store.targetPointerBits()))
          reject("invalid enumeration discriminant");
      if (r.vector &&
          (!isNumeric(r.vector->element) || !r.vector->lanes ||
           !r.vector->alignment || !std::has_single_bit(r.vector->alignment)))
        reject("invalid native vector shape");
      if ((r.kind == AggregateKind::NativeVector) != r.vector.has_value())
        reject("native vector shape mismatch");
      if (r.kind == AggregateKind::Array) {
        if (r.components.size() != 1 || !validType(r.components.front()) ||
            (r.arrayCount != Type::Unknown &&
             (!store.isConstant(r.arrayCount) ||
              !isInteger(store.parameter(r.arrayCount).valueType))))
          reject("invalid array type or typed count");
        if (r.arrayCount != Type::Unknown) {
          if (!r.fields.empty())
            reject("compact or symbolic array has expanded fields");
          auto literal = store.scalarConstantValue(r.arrayCount);
          if (literal && (literal->negative || literal->magnitude[1]))
            reject("invalid array count");
        }
        valueEdges[slot].clear();
        if (store.isProduct(r.components[0]) || store.isSlice(r.components[0]))
          edge(valueEdges, slot, r.components[0]);
      } else if (r.arrayCount != Type::Unknown)
        reject("array count on non-array product");
      if (imported->closure) {
        validateCallable(store, *imported->closure, false);
        if (imported->closure->environment != ids[i]) {
          bool derived = false;
          for (auto origin : {r.genericOrigin, r.regionOrigin})
            if (origin != Type::Unknown && store.isCallable(origin) &&
                store.callable(origin).environment ==
                    imported->closure->environment)
              derived = true;
          if (!derived)
            reject(
                "closure environment does not refer to its product or origin");
        }
      } else if (!imported->coroutineInterior.empty())
        reject("coroutine interior without closure");
      if (r.kind != AggregateKind::Product &&
          r.kind != AggregateKind::Enumeration &&
          r.kind != AggregateKind::NativeVector &&
          r.kind != AggregateKind::Opaque) {
        std::optional<std::size_t> arity;
        switch (r.kind) {
        case AggregateKind::Outcome:
        case AggregateKind::Coroutine:
          arity = 2;
          break;
        case AggregateKind::Tuple:
        case AggregateKind::Range:
          break;
        case AggregateKind::BorrowError:
        case AggregateKind::BorrowMutError:
        case AggregateKind::Ordering:
        case AggregateKind::PhantomPinned:
        case AggregateKind::VarArgs:
          arity = 0;
          break;
        default:
          arity = 1;
          break;
        }
        if (arity && r.components.size() != *arity)
          reject("structural aggregate component arity mismatch");
        for (auto component : r.components)
          if (!validType(component))
            reject("invalid structural aggregate component");
        auto fields = [&](std::span<const Type> expected) {
          if (r.fields.size() != expected.size())
            reject("structural aggregate field arity mismatch");
          for (std::size_t field = 0; field < expected.size(); ++field)
            if (r.fields[field].type != expected[field])
              reject("structural aggregate field type mismatch");
        };
        switch (r.kind) {
        case AggregateKind::Optional:
          fields(std::array{Type::I32, r.components[0]});
          break;
        case AggregateKind::Outcome:
          fields(std::array{Type::I32, r.components[0], r.components[1]});
          break;
        case AggregateKind::Tuple:
        case AggregateKind::Range:
          fields(r.components);
          break;
        case AggregateKind::Array:
          for (const auto &field : r.fields)
            if (field.type != r.components[0])
              reject("expanded array element type mismatch");
          break;
        case AggregateKind::RefCell:
          fields(std::array{Type::Isize, r.components[0]});
          break;
        case AggregateKind::Ref:
        case AggregateKind::RefMut: {
          auto source = r.components[0];
          if (!store.isView(source) ||
              !store.isProduct(store.view(source).payload) ||
              store.product(store.view(source).payload).kind !=
                  AggregateKind::RefCell ||
              store.product(store.view(source).payload).components.size() != 1)
            reject("invalid dynamic borrow guard payload");
          auto region = store.view(source).region;
          auto payload =
              store.product(store.view(source).payload).components[0];
          if (r.fields.size() != 2)
            reject("dynamic borrow guard field arity mismatch");
          for (unsigned field = 0; field < 2; ++field) {
            auto type = r.fields[field].type;
            auto mode = field == 1 && r.kind == AggregateKind::RefMut
                            ? ParameterMode::Mut
                            : ParameterMode::Read;
            bool valid = field == 0
                             ? store.isView(type) &&
                                   store.view(type).payload == Type::Isize &&
                                   store.view(type).mode == mode &&
                                   store.view(type).region == region
                             : store.isPointer(type) &&
                                   store.pointer(type).payload == payload &&
                                   store.pointer(type).mode == mode;
            if (!valid)
              reject("invalid dynamic borrow guard field");
          }
          break;
        }
        case AggregateKind::VarArgs: {
          std::vector<Type> representation;
          if (store.vaListAbi() == VaListAbi::Pointer)
            representation = {Type::Unknown};
          else if (store.vaListAbi() == VaListAbi::Aapcs64)
            representation = {Type::Unknown, Type::Unknown, Type::Unknown,
                              Type::I32, Type::I32};
          else
            representation = {Type::U32, Type::U32, Type::Unknown,
                              Type::Unknown};
          if (r.fields.size() != representation.size())
            reject("variadic cursor field arity mismatch");
          for (std::size_t field = 0; field < representation.size(); ++field) {
            auto actual = r.fields[field].type;
            if (representation[field] == Type::Unknown) {
              if (!store.isPointer(actual) ||
                  store.pointer(actual).payload != Type::Unit ||
                  store.pointer(actual).mode != ParameterMode::Mut)
                reject("invalid variadic cursor pointer field");
            } else if (actual != representation[field])
              reject("invalid variadic cursor offset field");
          }
          break;
        }
        case AggregateKind::Ordering:
          fields(std::array{Type::I32});
          break;
        case AggregateKind::PhantomPinned:
        case AggregateKind::BorrowError:
        case AggregateKind::BorrowMutError:
        case AggregateKind::Coroutine:
          fields({});
          break;
        default:
          fields(std::array{r.components[0]});
          break;
        }
      }
    } else if (auto parameter = definitionRecord<TypeParameter>(definition)) {
      const auto &r = *parameter;
      if ((r.kind == TypeParameterKind::Type &&
           (r.valueType != Type::Unknown || !r.operands.empty())) ||
          (r.kind == TypeParameterKind::Constant &&
           (!validType(r.valueType) || !r.operands.empty())) ||
          (r.kind == TypeParameterKind::Value &&
           (!scalar(r.valueType) || !r.operands.empty() ||
            (r.numeric.negative &&
             r.numeric.magnitude == std::array<std::uint64_t, 2>{}) ||
            !integerLiteralFits(r.numeric, r.valueType,
                                store.targetPointerBits()))))
        reject("invalid type or constant parameter '" + std::string(r.name) +
               "' (kind " + std::to_string(static_cast<unsigned>(r.kind)) +
               ", value type " + std::string(store.name(r.valueType)) +
               ", operands " + std::to_string(r.operands.size()) + ")");
      if (r.thin && (r.kind != TypeParameterKind::Type &&
                     (r.kind != TypeParameterKind::Projection ||
                      r.valueType != Type::Unknown)))
        reject("invalid Thin type parameter constraint");
      if (r.kind == TypeParameterKind::Expression) {
        static const std::set<std::string, std::less<>> operations{
            "+",  "-",  "*",  "/", "%",  "&", "|",  "^",  "<<",
            ">>", "==", "!=", "<", "<=", ">", ">=", "&&", "||"};
        if (!scalar(r.valueType) || r.operands.size() != 2 ||
            !operations.contains(r.operation) ||
            !store.isConstant(r.operands[0]) ||
            !store.isConstant(r.operands[1]))
          reject("invalid typed constant expression");
        auto left = store.parameter(r.operands[0]).valueType;
        auto right = store.parameter(r.operands[1]).valueType;
        bool shift = r.operation == "<<" || r.operation == ">>";
        bool comparison = r.operation == "==" || r.operation == "!=" ||
                          r.operation == "<" || r.operation == "<=" ||
                          r.operation == ">" || r.operation == ">=";
        bool logical = r.operation == "&&" || r.operation == "||";
        bool booleanBits =
            r.operation == "&" || r.operation == "|" || r.operation == "^";
        if ((shift ? !isInteger(left) || !isInteger(right) : left != right) ||
            r.valueType != (comparison || logical ? Type::Bool : left) ||
            (left == Type::Bool && !comparison && !logical && !booleanBits) ||
            (left == Type::Char && !comparison) ||
            (left != Type::Bool && logical))
          reject("invalid constant expression operand types");
        if (auto value = store.scalarConstantValue(r.operands[1])) {
          if (((r.operation == "/" || r.operation == "%") &&
               value->magnitude == std::array<std::uint64_t, 2>{}) ||
              (shift && (value->negative || value->magnitude[1] ||
                         value->magnitude[0] >=
                             integerWidth(left, store.targetPointerBits()))))
            reject("invalid constant expression arithmetic");
        }
        if (store.scalarConstantValue(r.operands[0]) &&
            store.scalarConstantValue(r.operands[1]))
          reject("noncanonical evaluated constant expression");
      }
      if (r.kind == TypeParameterKind::Projection) {
        if (r.operands.size() < 2 || !validType(r.operands[0]) ||
            !store.isErased(r.operands[1]) || r.value < 0)
          reject("invalid interface projection subject, owner, or ordinal");
        if (r.valueType != Type::Unknown && !validType(r.valueType))
          reject("invalid interface projection result type");
      }
      for (auto constraint : {r.callableConstraint, r.erasedCallableConstraint})
        if (constraint != Type::Unknown && !store.isFunctionPointer(constraint))
          reject("invalid callable parameter constraint");
      if (r.callableConstraint != Type::Unknown)
        for (auto local : r.callableLocalParameters)
          if (local >= store.callable(r.callableConstraint).parameters.size())
            reject("dangling callable constraint parameter");
    } else if (auto callable = definitionRecord<CallableType>(definition))
      validateCallable(store, *callable, true);
    else if (auto erased = definitionRecord<ErasedType>(definition)) {
      for (const auto &method : erased->methods)
        validateCallable(store, method, false);
      if ((!erased->methodTypes.empty() &&
           erased->methodTypes.size() != erased->methods.size()) ||
          erased->methodOwners.size() != erased->methodSlots.size())
        reject("erased interface dispatch arity mismatch");
      std::set<Type> associated;
      for (const auto &binding : erased->associated) {
        if ((!store.isParameter(binding.parameter) &&
             !store.isConstant(binding.parameter)) ||
            !associated.insert(binding.parameter).second)
          reject("invalid or duplicate erased associated binding");
        const auto &parameter = store.parameter(binding.parameter);
        if (parameter.kind == TypeParameterKind::Type) {
          if (!validType(binding.argument))
            reject("invalid erased associated type binding");
        } else if (parameter.kind == TypeParameterKind::Constant) {
          if (!store.isConstant(binding.argument) ||
              !validType(store.parameter(binding.argument).valueType))
            reject("erased associated constant requires a typed value");
          if (parameter.valueType.index() < builtinTypeCount &&
              parameter.valueType !=
                  store.parameter(binding.argument).valueType)
            reject("erased associated constant value type mismatch");
        } else
          reject("erased associated binding key is not a declaration");
      }
      for (auto method : erased->methodTypes)
        if (method != Type::Unknown && !store.isFunctionPointer(method))
          reject("invalid erased method type");
      for (auto owner : erased->methodOwners)
        if (!store.isErased(owner))
          reject("invalid erased method owner");
      for (auto parent : erased->parentInterfaces) {
        if (!store.isErased(parent))
          reject("invalid erased parent interface");
        edge(interfaceEdges, slot, parent);
      }
    } else if (auto view = definitionRecord<ViewType>(definition)) {
      if (!validType(view->payload) || (view->mode != ParameterMode::Read &&
                                        view->mode != ParameterMode::Mut))
        reject("invalid view type");
    } else if (auto pointer = definitionRecord<ImportedPointer>(definition)) {
      if (!validType(pointer->descriptor.payload) ||
          pointer->descriptor.region != RegionId::Unspecified ||
          (pointer->descriptor.mode != ParameterMode::Read &&
           pointer->descriptor.mode != ParameterMode::Mut))
        reject("invalid pointer type");
    } else if (auto slice = definitionRecord<SliceType>(definition)) {
      if (!validType(slice->element) ||
          slice->metadata != PointerMetadata::ElementCount)
        reject("invalid slice element");
      if (store.isProduct(slice->element) || store.isSlice(slice->element))
        edge(valueEdges, slot, slice->element);
    }
  }
  acyclic(originEdges);
  acyclic(interfaceEdges);
  auto order = acyclic(valueEdges);
  std::vector<bool> drops(valueEdges.size());
  std::vector<std::uint64_t> expanded(valueEdges.size(), 1),
      elements(valueEdges.size(), 1);
  auto drop = [&](Type type) {
    if (store.isErased(type))
      return true;
    if (store.isParameter(type))
      return !store.parameter(type).copyRequested;
    return (store.isProduct(type) || store.isSlice(type)) && drops[node(type)];
  };
  for (auto slot : order) {
    auto i = selected ? ordinals[slot] : slot;
    if (proofs) {
      if (auto found = proofs->find(i); found != proofs->end()) {
        drops[slot] = found->second.drops;
        expanded[slot] = found->second.expanded;
        elements[slot] = found->second.elements;
        continue;
      }
    }
    auto type = ids[i];
    if (store.isSlice(type))
      drops[slot] = drop(store.slice(type).element);
    else if (store.isErased(type) || store.isParameter(type))
      drops[slot] = drop(type);
    else if (store.isProduct(type)) {
      const auto &r = store.product(type);
      bool suppress = r.kind == AggregateKind::Uninit ||
                      r.kind == AggregateKind::ManualDrop ||
                      r.kind == AggregateKind::Atomic;
      drops[slot] = !suppress && (r.hasDestructor ||
                                  r.nativeCleanup != NativeCleanup::None ||
                                  r.kind == AggregateKind::VarArgs ||
                                  r.kind == AggregateKind::Coroutine);
      if (!suppress)
        for (const auto &field : r.fields)
          drops[slot] = drops[slot] || drop(field.type);
      if (r.kind != AggregateKind::Array)
        continue;
      auto element = r.components[0];
      auto literal = r.arrayCount == Type::Unknown
                         ? std::optional<NumericLiteral>{}
                         : store.scalarConstantValue(r.arrayCount);
      auto length = r.arrayCount == Type::Unknown
                        ? std::optional<std::uint64_t>{r.fields.size()}
                    : literal ? std::optional{literal->magnitude[0]}
                              : std::nullopt;
      auto inner = element.index() >= builtinTypeCount &&
                           store.isProduct(element) &&
                           store.product(element).kind == AggregateKind::Array
                       ? node(element)
                       : valueEdges.size();
      auto expandedInner = inner == valueEdges.size() ? 1 : expanded[inner];
      auto elementsInner = inner == valueEdges.size() ? 1 : elements[inner];
      auto product = [](std::uint64_t count, std::uint64_t inner,
                        std::uint64_t limit) {
        return count > limit / inner ? limit + 1 : count * inner;
      };
      expanded[slot] = product(std::max<std::uint64_t>(1, length.value_or(1)),
                               expandedInner, TypeStore::expandedArrayTotal);
      elements[slot] =
          product(std::max<std::uint64_t>(1, length.value_or(1)), elementsInner,
                  TypeStore::droppableArrayElements);
      if (r.arrayCount != Type::Unknown)
        drops[slot] = drops[slot] || drop(element);
      if (!length)
        continue;
      bool compact =
          !drop(element) &&
          (*length > TypeStore::expandedArrayLimit ||
           product(*length, expandedInner, TypeStore::expandedArrayTotal) >
               TypeStore::expandedArrayTotal);
      if (compact != (r.arrayCount != Type::Unknown))
        reject("noncanonical compact or expanded array representation");
      if (drop(element) &&
          product(*length, elementsInner, TypeStore::droppableArrayElements) >
              TypeStore::droppableArrayElements)
        reject("droppable array exceeds compiler resource limit");
      if (literal) {
        auto expected =
            *length <= static_cast<std::uint64_t>(INT32_MAX)   ? Type::I32
            : *length <= static_cast<std::uint64_t>(INT64_MAX) ? Type::I64
                                                               : Type::U64;
        if (store.parameter(r.arrayCount).valueType != expected)
          reject("noncanonical typed compact array count");
      }
    }
  }
  if (proofs)
    for (std::size_t slot = 0; slot < ordinals.size(); ++slot)
      proofs->try_emplace(
          ordinals[slot],
          TypeGraphProof{expanded[slot], elements[slot], drops[slot]});
}
struct Remap : SemanticWalk<Remap> {
  using SemanticWalk::value;
  std::function<Type(Type)> map;
  explicit Remap(std::function<Type(Type)> map) : map(std::move(map)) {}
  void value(Type &type) { type = map(type); }
};
bool equalDefinition(ImportedTypeDefinition left,
                     ImportedTypeDefinition right) {
  if (left.index() != right.index())
    return false;
  auto clearNames = [](ImportedTypeDefinition &definition) {
    if (auto callable = std::get_if<CallableType>(&definition)) {
      callable->name.clear();
      for (auto &parameter : callable->parameters)
        parameter.name.clear();
      for (auto &region : callable->regions)
        region.clear();
    } else if (auto parameter = std::get_if<TypeParameter>(&definition))
      parameter->name.clear();
    else if (auto view = std::get_if<ViewType>(&definition))
      view->name.clear();
    else if (auto pointer = std::get_if<ImportedPointer>(&definition))
      pointer->descriptor.name.clear();
    else if (auto slice = std::get_if<SliceType>(&definition))
      slice->name.clear();
    else if (auto erased = std::get_if<ErasedType>(&definition))
      erased->name.clear();
    else if (!nominal(definition))
      std::get<ImportedProduct>(definition).descriptor.name.clear();
  };
  clearNames(left);
  clearNames(right);
  Writer a, b;
  std::visit([&](auto &r) { a(r); }, left);
  std::visit([&](auto &r) { b(r); }, right);
  return a.bytes == b.bytes;
}
struct ReferenceShape : SemanticWalk<ReferenceShape> {
  using SemanticWalk::value;
  std::vector<Type> types;
  std::vector<RegionId> regions;
  std::vector<RegionUniverse> universes;
  void value(Type &type) {
    types.push_back(type);
    type = Type::Unknown;
  }
  void value(RegionId &region) {
    regions.push_back(region);
    region = RegionId::Unspecified;
  }
  void universe(RegionUniverse &universe) {
    universes.push_back(universe);
    universe = 0;
  }
};
struct ExistingGraph {
  std::map<Type, Type> types;
  std::map<RegionId, RegionId> regions;
  std::map<RegionUniverse, RegionUniverse> universes{{0, 0}};
  std::map<RegionBinder, RegionBinder> binders;
};
ExistingGraph
matchExisting(const TypeStore &decoded, const TypeStore &consumer,
              std::span<const Type> ids,
              const std::vector<std::optional<DefinitionIdentity>> &logical,
              const TypeGraphSymbols &symbols) {
  ExistingGraph result;
  if (!symbols.lookupDefinition)
    return result;
  std::vector<std::pair<Type, Type>> pending;
  std::map<Type, DefinitionIdentity> owners;
  std::map<RegionUniverse, RegionUniverse> reverseUniverses{{0, 0}};
  for (std::size_t i = 0; i < ids.size(); ++i)
    if (logical[i])
      if (auto existing = symbols.lookupDefinition(*logical[i])) {
        if (!consumer.contains(*existing))
          reject("logical definition resolves to a missing type");
        auto [owner, added] = owners.emplace(*existing, *logical[i]);
        if (!added && owner->second != *logical[i])
          reject("distinct logical definitions resolve to the same type");
        result.types.emplace(ids[i], *existing);
        pending.emplace_back(ids[i], *existing);
      }
  auto universe = [&](RegionUniverse source, RegionUniverse target) {
    while (true) {
      if (auto mapped = result.universes.find(source);
          mapped != result.universes.end()) {
        if (mapped->second != target)
          reject("conflicting logical region universe");
        break;
      }
      if (!target)
        reject("incompatible logical region universe ancestry");
      auto [reverse, added] = reverseUniverses.emplace(target, source);
      if (!added && reverse->second != source)
        reject("distinct logical universes resolve to the same universe");
      result.universes.emplace(source, target);
      source = decoded.regions().universeParent(source);
      target = consumer.regions().universeParent(target);
    }
  };
  std::vector<std::pair<RegionId, RegionId>> intersections;
  std::map<RegionBinder, RegionBinder> reverseBinders;
  std::map<RegionId, RegionId> reverseRegions;
  auto region = [&](RegionId source, RegionId target) {
    auto [mapped, added] = result.regions.emplace(source, target);
    if (!added) {
      if (mapped->second != target)
        reject("conflicting logical region identity");
      return;
    }
    const auto &a = decoded.regions().get(source);
    const auto &b = consumer.regions().get(target);
    if (a.kind != b.kind)
      reject("incompatible logical region kind");
    auto [reverse, reverseFresh] = reverseRegions.emplace(target, source);
    if (!reverseFresh && reverse->second != source)
      reject("distinct logical regions resolve to the same region");
    if (a.kind == RegionKind::Intersection) {
      if (a.sources.size() != b.sources.size())
        reject("incompatible logical region intersection");
      intersections.emplace_back(source, target);
    } else if (a.kind != RegionKind::Unspecified &&
               a.kind != RegionKind::Static) {
      auto [binder, fresh] = result.binders.emplace(a.binder, b.binder);
      auto [reverse, reverseFresh] = reverseBinders.emplace(b.binder, a.binder);
      if ((!fresh && binder->second != b.binder) ||
          (!reverseFresh && reverse->second != a.binder))
        reject("incompatible logical region binder equality");
      universe(a.universe, b.universe);
    }
  };
  std::set<std::pair<Type, Type>> visited;
  for (std::size_t next = 0; next < pending.size(); ++next) {
    auto [source, target] = pending[next];
    if (!visited.emplace(source, target).second)
      continue;
    if (source.index() < builtinTypeCount) {
      if (source != target)
        reject("conflicting logical primitive type");
      continue;
    }
    if (target.index() < builtinTypeCount ||
        decoded.importedKind(source) != consumer.importedKind(target))
      reject("conflicting logical type family");
    auto [mapped, added] = result.types.emplace(source, target);
    if (!added && mapped->second != target)
      reject("conflicting logical type identity");
    auto a = decoded.importedDefinition(source);
    auto b = consumer.importedDefinition(target);
    for (auto *definition : {&a, &b})
      if (auto product = std::get_if<ImportedProduct>(definition);
          product && !nominal(*definition))
        product->descriptor.name.clear();
    if (auto erased = std::get_if<ErasedType>(&a))
      std::sort(erased->associated.begin(), erased->associated.end(),
                [&](const auto &left, const auto &right) {
                  auto key = [&](Type type) {
                    auto existing = result.types.find(type);
                    return existing == result.types.end() ? type
                                                          : existing->second;
                  };
                  return key(left.parameter) < key(right.parameter);
                });
    ReferenceShape left, right;
    std::visit([&](auto &r) { left(r); }, a);
    std::visit([&](auto &r) { right(r); }, b);
    if (!equalDefinition(a, b) || left.types.size() != right.types.size() ||
        left.regions.size() != right.regions.size() ||
        left.universes.size() != right.universes.size())
      reject("conflicting logical definition contract");
    for (std::size_t i = 0; i < left.types.size(); ++i)
      pending.emplace_back(left.types[i], right.types[i]);
    for (std::size_t i = 0; i < left.regions.size(); ++i)
      region(left.regions[i], right.regions[i]);
    for (std::size_t i = 0; i < left.universes.size(); ++i)
      universe(left.universes[i], right.universes[i]);
  }
  struct Partition {
    std::map<RegionId, std::vector<std::size_t>> incidence;
    std::map<RegionId, std::uint32_t> leaves;
    std::map<RegionBinder, std::vector<RegionId>> members;
    std::map<RegionBinder, std::uint32_t> binders;
    std::map<RegionUniverse, std::vector<RegionBinder>> scopes;
    std::map<RegionUniverse, std::vector<RegionUniverse>> children;
    std::map<RegionUniverse, std::uint32_t> worlds;
  };
  Partition a, b;
  for (std::size_t i = 0; i < intersections.size(); ++i) {
    for (auto leaf : decoded.regions().get(intersections[i].first).sources)
      a.incidence[leaf].push_back(i);
    for (auto leaf : consumer.regions().get(intersections[i].second).sources)
      b.incidence[leaf].push_back(i);
  }
  for (auto [source, target] : result.regions)
    if (source != RegionId::Unspecified && source != RegionId::Static &&
        decoded.regions().get(source).kind != RegionKind::Intersection) {
      a.incidence.try_emplace(source);
      b.incidence.try_emplace(target);
    }
  using LeafKey =
      std::tuple<RegionKind, std::vector<std::size_t>, std::optional<RegionId>>;
  using WorldKey =
      std::tuple<std::optional<RegionUniverse>, std::vector<std::uint32_t>,
                 std::vector<std::uint32_t>>;
  std::map<LeafKey, std::uint32_t> leafColors;
  std::map<std::vector<std::uint32_t>, std::uint32_t> binderColors;
  std::map<WorldKey, std::uint32_t> worldColors;
  auto color = [](auto &colors, auto key) {
    return colors
        .try_emplace(std::move(key), static_cast<std::uint32_t>(colors.size()))
        .first->second;
  };
  auto partition = [&](Partition &p, const RegionStore &store, bool source) {
    auto addWorld = [&](RegionUniverse world) {
      while (p.scopes.try_emplace(world).second && world) {
        auto parent = store.universeParent(world);
        p.children[parent].push_back(world);
        world = parent;
      }
    };
    addWorld(0);
    for (auto [from, to] : result.universes)
      addWorld(source ? from : to);
    for (const auto &[leaf, incidence] : p.incidence) {
      const auto &r = store.get(leaf);
      std::optional<RegionId> anchor;
      if (source) {
        if (auto known = result.regions.find(leaf);
            known != result.regions.end())
          anchor = known->second;
      } else if (reverseRegions.contains(leaf))
        anchor = leaf;
      p.leaves.emplace(leaf,
                       color(leafColors, LeafKey{r.kind, incidence, anchor}));
      if (p.members[r.binder].empty()) {
        addWorld(r.universe);
        p.scopes[r.universe].push_back(r.binder);
      }
      p.members[r.binder].push_back(leaf);
    }
    for (const auto &[binder, leaves] : p.members) {
      std::vector<std::uint32_t> colors;
      for (auto leaf : leaves)
        colors.push_back(p.leaves.at(leaf));
      std::sort(colors.begin(), colors.end());
      p.binders.emplace(binder, color(binderColors, std::move(colors)));
    }
    for (auto world = p.scopes.rbegin(); world != p.scopes.rend(); ++world) {
      std::optional<RegionUniverse> anchor;
      if (source) {
        if (auto known = result.universes.find(world->first);
            known != result.universes.end())
          anchor = known->second;
      } else if (reverseUniverses.contains(world->first))
        anchor = world->first;
      std::vector<std::uint32_t> binders, children;
      for (auto binder : world->second)
        binders.push_back(p.binders.at(binder));
      for (auto child : p.children[world->first])
        children.push_back(p.worlds.at(child));
      std::sort(binders.begin(), binders.end());
      std::sort(children.begin(), children.end());
      p.worlds.emplace(world->first,
                       color(worldColors, WorldKey{anchor, std::move(binders),
                                                   std::move(children)}));
    }
  };
  partition(a, decoded.regions(), true);
  partition(b, consumer.regions(), false);
  if (a.worlds.at(0) != b.worlds.at(0))
    reject("incompatible logical region graph");
  std::vector<std::pair<RegionUniverse, RegionUniverse>> worlds{{0, 0}};
  for (std::size_t next = 0; next < worlds.size(); ++next) {
    auto [source, target] = worlds[next];
    universe(source, target);
    std::map<std::uint32_t, std::vector<RegionUniverse>> children;
    for (auto child : b.children[target])
      children[b.worlds.at(child)].push_back(child);
    for (auto child : a.children[source]) {
      auto &choices = children[a.worlds.at(child)];
      if (choices.empty())
        reject("missing logical region universe");
      worlds.emplace_back(child, choices.back());
      choices.pop_back();
    }
    std::map<std::uint32_t, std::vector<RegionBinder>> binders;
    for (auto binder : b.scopes[target])
      binders[b.binders.at(binder)].push_back(binder);
    for (auto binder : a.scopes[source]) {
      auto &choices = binders[a.binders.at(binder)];
      if (choices.empty())
        reject("missing logical region binder");
      auto targetBinder = choices.back();
      choices.pop_back();
      std::map<std::uint32_t, std::vector<RegionId>> leaves;
      for (auto leaf : b.members[targetBinder])
        leaves[b.leaves.at(leaf)].push_back(leaf);
      for (auto leaf : a.members[binder]) {
        auto &matches = leaves[a.leaves.at(leaf)];
        if (matches.empty())
          reject("missing logical intersection source");
        region(leaf, matches.back());
        matches.pop_back();
      }
    }
  }
  return result;
}
struct RegionRemap : SemanticWalk<RegionRemap> {
  using SemanticWalk::value;
  const std::map<RegionId, RegionId> &regions;
  const std::map<RegionUniverse, RegionUniverse> &universes;
  RegionRemap(const std::map<RegionId, RegionId> &regions,
              const std::map<RegionUniverse, RegionUniverse> &universes)
      : regions(regions), universes(universes) {}
  void value(Type &) {}
  void value(RegionId &region) { region = regions.at(region); }
  void universe(RegionUniverse &universe) { universe = universes.at(universe); }
};
void remapRegionGraph(TypeStore &candidate, const TypeStore &decoded,
                      const Tables &tables,
                      const std::vector<RegionId> &sourceRegions,
                      const std::vector<RegionUniverse> &sourceUniverses,
                      ExistingGraph &existing,
                      std::vector<ImportedTypeDefinition> &definitions) {
  auto &store = candidate.regions();
  std::vector<RegionUniverse> universes{0};
  for (std::size_t i = 1; i < tables.parents.size(); ++i) {
    auto source = sourceUniverses[i];
    if (auto found = existing.universes.find(source);
        found != existing.universes.end())
      universes.push_back(found->second);
    else {
      auto target = store.binder(universes[tables.parents[i]], true).universe;
      universes.push_back(target);
      existing.universes.emplace(source, target);
    }
  }
  std::vector<std::optional<RegionScope>> scopes(tables.binders.size());
  for (std::size_t i = 0; i < tables.regions.size(); ++i) {
    const auto &r = tables.regions[i];
    if (r.kind == RegionKind::Intersection)
      continue;
    const auto &source = decoded.regions().get(sourceRegions[i + 2]);
    if (auto binder = existing.binders.find(source.binder);
        binder != existing.binders.end())
      scopes[r.binder] = RegionScope{binder->second, universes[r.universe]};
  }
  for (std::size_t i = 0; i < scopes.size(); ++i)
    if (!scopes[i])
      scopes[i] = store.binder(universes[tables.binders[i]]);
  existing.regions.emplace(RegionId::Unspecified, RegionId::Unspecified);
  existing.regions.emplace(RegionId::Static, RegionId::Static);
  for (std::size_t i = 0; i < tables.regions.size(); ++i) {
    const auto &r = tables.regions[i];
    auto source = sourceRegions[i + 2];
    if (r.kind == RegionKind::Intersection || existing.regions.contains(source))
      continue;
    auto scope = *scopes[r.binder];
    RegionId target;
    switch (r.kind) {
    case RegionKind::Bound:
      target = store.bound(scope, r.name);
      break;
    case RegionKind::Rigid:
      target = store.rigid(scope, r.name);
      break;
    case RegionKind::Inference:
      target = store.inference(scope);
      break;
    case RegionKind::Local:
      target = store.local(scope);
      break;
    default:
      reject("invalid remapped region kind");
    }
    existing.regions.emplace(source, target);
  }
  for (std::size_t i = 0; i < tables.regions.size(); ++i)
    if (tables.regions[i].kind == RegionKind::Intersection) {
      std::vector<RegionId> sources;
      for (auto ref : tables.regions[i].sources)
        sources.push_back(existing.regions.at(sourceRegions[ref]));
      auto target = store.intersection(std::move(sources));
      auto [mapped, added] =
          existing.regions.emplace(sourceRegions[i + 2], target);
      if (!added && mapped->second != target)
        reject("conflicting remapped region intersection");
    }
  RegionRemap mapper(existing.regions, existing.universes);
  for (auto &definition : definitions)
    std::visit([&](auto &r) { mapper(r); }, definition);
}
template <class Definition>
void writeCanonicalKey(Writer &key, const Definition &definition) {
  const auto *mapper = key.typeMapper;
  key.byte(static_cast<std::uint8_t>(definition.index()));
  visitDefinition(
      [&](const auto &r) {
        using T = std::decay_t<decltype(r)>;
        if constexpr (std::is_same_v<T, ImportedProduct> ||
                      std::is_same_v<T, ImportedProductView> ||
                      std::is_same_v<T, CompactProduct>) {
          auto &p = r.descriptor;
          if (p.regionOrigin != Type::Unknown) {
            key.byte(0);
            key(p.regionOrigin, p.normalizedFields, p.regionArguments,
                p.genericArguments, p.fields);
          } else if (p.genericOrigin != Type::Unknown) {
            key.byte(1);
            key(p.genericOrigin, p.genericArguments);
            if (p.kind == AggregateKind::Opaque) {
              std::vector<Type> hidden;
              for (const auto &field : p.fields)
                hidden.push_back(field.type);
              key(hidden, p.opaqueBounds);
            }
          } else {
            key.byte(2);
            key(p.kind, p.components);
            if (p.kind == AggregateKind::Array) {
              key(p.arrayCount);
              if (p.arrayCount == Type::Unknown)
                key.u64(p.fields.size());
            }
          }
        } else if constexpr (std::is_same_v<T, TypeParameter> ||
                             std::is_same_v<T, CompactParameter>) {
          key(r.kind);
          switch (r.kind) {
          case TypeParameterKind::Value:
            key(r.valueType, r.numeric);
            break;
          case TypeParameterKind::Expression:
            key(r.operation, r.operands);
            break;
          case TypeParameterKind::Projection:
            key(r.operands, r.value, r.valueType, r.copyRequested, r.sized,
                r.thin, r.regionArguments);
            break;
          default:
            reject("generic definition has no structural identity");
          }
        } else if constexpr (std::is_same_v<T, CallableType> ||
                             std::is_same_v<T, CompactCallable>) {
          key.omitCallableNames = true;
          key(r);
          key.omitCallableNames = false;
        } else if constexpr (std::is_same_v<T, ErasedType> ||
                             std::is_same_v<T, CompactErased>) {
          if (key.symbolFixups)
            key.symbolFixups->push_back(
                {key.bytes.size(), SymbolKind::Interface, r.declaration, 8});
          key(r.declaration, r.arguments);
          std::vector<TypeBinding> associated(r.associated.begin(),
                                              r.associated.end());
          if (mapper)
            for (auto &binding : associated) {
              binding.parameter = (*mapper)(binding.parameter);
              binding.argument = (*mapper)(binding.argument);
            }
          std::sort(associated.begin(), associated.end(),
                    [](const auto &a, const auto &b) {
                      return a.parameter < b.parameter;
                    });
          key.typeMapper = nullptr;
          key(associated);
          key.typeMapper = mapper;
          key(r.regionArguments, r.regionParameters, r.regionRequirements,
              r.bound, r.regionUniverse);
        } else if constexpr (std::is_same_v<T, ViewType> ||
                             std::is_same_v<T, CompactView>)
          key(r.payload, r.mode, r.region);
        else if constexpr (std::is_same_v<T, ImportedPointer> ||
                           std::is_same_v<T, ImportedPointerView> ||
                           std::is_same_v<T, CompactPointer>)
          key(r.descriptor.payload, r.descriptor.mode);
        else
          key(r.element);
      },
      definition);
}
template <class Definition>
std::string canonicalKey(const Definition &definition,
                         std::vector<Type> *references = nullptr,
                         const std::function<Type(Type)> *mapper = nullptr,
                         std::uint64_t *fingerprint = nullptr) {
  Writer key;
  key.typeReferences = references;
  key.discardBytes = references != nullptr;
  key.typeMapper = mapper;
  key.fingerprint = fingerprint;
  writeCanonicalKey(key, definition);
  if (key.discardBytes)
    return {};
  return {reinterpret_cast<const char *>(key.bytes.data()), key.bytes.size()};
}
struct FlatTypeEdges {
  std::vector<std::size_t> offsets{0}, targets;
  std::vector<bool> removed;
  std::size_t size() const { return offsets.size() - 1; }
  std::span<const std::size_t> operator[](std::size_t node) const {
    if (!removed.empty() && removed[node])
      return {};
    return std::span(targets).subspan(offsets[node],
                                      offsets[node + 1] - offsets[node]);
  }
  void clear(std::size_t node) {
    if (removed.empty())
      removed.resize(size());
    removed[node] = true;
  }
};
template <class Regional>
std::vector<bool> recursiveRegionals(FlatTypeEdges edges, Regional regional) {
  if (acyclic(edges, true).size() == edges.size())
    return std::vector<bool>(edges.size());
  FlatTypeEdges reverse;
  reverse.offsets.resize(edges.size() + 1);
  for (std::size_t i = 0; i < edges.size(); ++i)
    for (auto target : edges[i])
      ++reverse.offsets[target + 1];
  for (std::size_t i = 1; i < reverse.offsets.size(); ++i)
    reverse.offsets[i] += reverse.offsets[i - 1];
  reverse.targets.resize(edges.targets.size());
  auto positions = reverse.offsets;
  for (std::size_t i = 0; i < edges.size(); ++i)
    for (auto target : edges[i])
      reverse.targets[positions[target]++] = i;
  struct Frame {
    std::size_t node, next = 0;
  };
  std::vector<Frame> stack;
  std::vector<bool> visited(edges.size()), recursive(edges.size());
  std::vector<std::size_t> order;
  for (std::size_t root = 0; root < edges.size(); ++root) {
    if (visited[root])
      continue;
    visited[root] = true;
    stack.push_back({root});
    while (!stack.empty()) {
      auto &frame = stack.back();
      if (frame.next == edges[frame.node].size()) {
        order.push_back(frame.node);
        stack.pop_back();
      } else {
        auto child = edges[frame.node][frame.next++];
        if (!visited[child]) {
          visited[child] = true;
          stack.push_back({child});
        }
      }
    }
  }
  std::fill(visited.begin(), visited.end(), false);
  std::vector<std::size_t> pending, component;
  for (auto root = order.rbegin(); root != order.rend(); ++root) {
    if (visited[*root])
      continue;
    component.clear();
    pending.push_back(*root);
    visited[*root] = true;
    while (!pending.empty()) {
      auto node = pending.back();
      pending.pop_back();
      component.push_back(node);
      for (auto parent : reverse[node])
        if (!visited[parent]) {
          visited[parent] = true;
          pending.push_back(parent);
        }
    }
    bool cycle = component.size() > 1 ||
                 std::find(edges[*root].begin(), edges[*root].end(), *root) !=
                     edges[*root].end();
    if (!cycle)
      continue;
    for (auto node : component)
      if (regional(node)) {
        recursive[node] = true;
        edges.clear(node);
      }
  }
  acyclic(edges);
  return recursive;
}
template <class Definitions>
std::vector<bool> recursiveRegionals(std::span<const Type> ids,
                                     const Definitions &definitions,
                                     bool *uniqueKeys = nullptr) {
  std::unordered_multimap<std::uint64_t, std::size_t> keys;
  if (uniqueKeys) {
    *uniqueKeys = true;
    keys.reserve(ids.size());
  }
  FlatTypeEdges edges;
  edges.offsets.reserve(ids.size() + 1);
  std::vector<Type> references;
  for (std::size_t i = 0; i < ids.size(); ++i) {
    references.clear();
    if (!nominal(definitions[i])) {
      std::uint64_t fingerprint = 14695981039346656037ull;
      canonicalKey(definitions[i], &references, nullptr,
                   uniqueKeys ? &fingerprint : nullptr);
      if (uniqueKeys) {
        auto [first, last] = keys.equal_range(fingerprint);
        if (first != last) {
          auto key = canonicalKey(definitions[i]);
          for (auto entry = first; entry != last; ++entry)
            if (canonicalKey(definitions[entry->second]) == key) {
              *uniqueKeys = false;
              return {};
            }
        }
        keys.emplace(fingerprint, i);
      }
      for (auto reference : references)
        if (reference.index() >= builtinTypeCount)
          edges.targets.push_back(graphIndex(ids, reference));
    }
    edges.offsets.push_back(edges.targets.size());
  }
  return recursiveRegionals(std::move(edges), [&](std::size_t node) {
    auto product = definitionRecord<ImportedProduct>(definitions[node]);
    return product && product->descriptor.regionOrigin != Type::Unknown;
  });
}
class CanonicalImport {
public:
  CanonicalImport(const TypeStore &original, TypeStore &candidate,
                  const TypeStore &decoded, std::span<const Type> ids,
                  std::vector<ImportedTypeDefinition> &definitions,
                  const std::vector<std::optional<DefinitionIdentity>> &logical,
                  const ExistingGraph &existing)
      : original(original), candidate(candidate), ids(ids),
        definitions(definitions), mapped(ids.size()), state(ids.size()),
        installed(ids.size()) {
    auto stored = original.storedTypes();
    canonicalTypes.reserve(ids.size() + stored.size());
    for (auto type : stored) {
      auto definition = original.importedDefinition(type);
      if (!nominal(definition))
        canonicalTypes.try_emplace(canonicalKey(definition), type);
    }
    for (const auto &[source, target] : existing.types) {
      auto i = graphIndex(ids, source);
      mapped[i] = target;
      state[i] = 2;
    }
    for (std::size_t i = 0; i < ids.size(); ++i) {
      if (!logical[i])
        continue;
      if (auto found = existing.types.find(ids[i]);
          found != existing.types.end()) {
        if (!original.contains(found->second) ||
            original.importedKind(found->second) !=
                decoded.importedKind(ids[i]))
          reject("logical definition resolves to an incompatible type");
        mapped[i] = found->second;
      }
      if (mapped[i] == Type::Unknown)
        mapped[i] = candidate.declareImportedType(decoded.importedKind(ids[i]));
      state[i] = 2;
    }
    auto recursive = recursiveRegionals(ids, definitions);
    for (std::size_t i = 0; i < ids.size(); ++i)
      if (recursive[i] && state[i] != 2) {
        mapped[i] = candidate.declareImportedType(ImportedTypeKind::Product);
        state[i] = 2;
      }
  }
  Type build(Type source) {
    if (source.index() < builtinTypeCount)
      return source;
    auto i = graphIndex(ids, source);
    if (state[i] == 2)
      return mapped[i];
    if (state[i] == 1)
      reject("cyclic structural type identity");
    if (++depth > limits::typeDepth)
      reject("imported type nesting exceeds compiler depth limit");
    state[i] = 1;
    std::function<Type(Type)> mapper = [&](Type type) { return build(type); };
    auto key = canonicalKey(definitions[i], nullptr, &mapper);
    if (auto existing = canonicalTypes.find(key);
        existing != canonicalTypes.end())
      mapped[i] = existing->second;
    else {
      mapped[i] = candidate.declareImportedType(
          static_cast<ImportedTypeKind>(definitions[i].index()));
      canonicalTypes.emplace(std::move(key), mapped[i]);
    }
    state[i] = 2;
    --depth;
    return mapped[i];
  }
  void finish() {
    for (auto type : ids)
      build(type);
    const auto base = builtinTypeCount + original.storedTypes().size();
    std::vector<std::size_t> lastInstalled(ids.size(), ids.size());
    for (std::size_t i = 0; i < ids.size(); ++i) {
      install(i);
      if (!original.contains(mapped[i]))
        lastInstalled[mapped[i].index() - base] = i;
    }
    for (std::size_t i = 0; i < ids.size(); ++i) {
      // The last installed definition is the candidate definition itself.
      if (!original.contains(mapped[i]) &&
          lastInstalled[mapped[i].index() - base] == i)
        continue;
      auto expected = definitions[i];
      remap(expected);
      if (!equalDefinition(expected, candidate.importedDefinition(mapped[i])))
        reject("conflicting logical or structural type definition");
    }
  }

private:
  const TypeStore &original;
  TypeStore &candidate;
  std::span<const Type> ids;
  std::vector<ImportedTypeDefinition> &definitions;
  std::unordered_map<std::string, Type> canonicalTypes;
  std::vector<Type> mapped;
  std::vector<unsigned char> state, installed;
  unsigned depth = 0;
  void remap(ImportedTypeDefinition &definition) {
    Remap mapper([&](Type type) { return build(type); });
    std::visit([&](auto &r) { mapper(r); }, definition);
    if (auto erased = std::get_if<ErasedType>(&definition))
      std::sort(erased->associated.begin(), erased->associated.end(),
                [](const auto &a, const auto &b) {
                  return a.parameter < b.parameter;
                });
  }
  void install(std::size_t i) {
    if (installed[i] || state[i] != 2)
      return;
    installed[i] = 1;
    if (original.contains(mapped[i]))
      return;
    auto definition = definitions[i];
    remap(definition);
    candidate.defineImportedType(mapped[i], std::move(definition));
  }
};
} // namespace

namespace {
template <class Definition>
auto identityDefinition(const Definition &value,
                        CompactArena *arena = nullptr) {
  using Result =
      std::conditional_t<std::is_same_v<Definition, ImportedTypeDefinition>,
                         ImportedTypeDefinition, CompactDefinition>;
  return visitDefinition(
      [&](const auto &source) -> Result {
        using T = std::decay_t<decltype(source)>;
        if constexpr (std::is_same_v<T, ImportedProduct> ||
                      std::is_same_v<T, CompactProduct>) {
          T result{};
          auto &target = result.descriptor;
          const auto &record = source.descriptor;
          target.name = record.name;
          target.kind = record.kind;
          target.components = record.components;
          target.genericOrigin = record.genericOrigin;
          target.genericArguments = record.genericArguments;
          target.regionOrigin = record.regionOrigin;
          target.regionArguments = record.regionArguments;
          target.normalizedFields = record.normalizedFields;
          target.arrayCount = record.arrayCount;
          if (record.regionOrigin != Type::Unknown ||
              (record.genericOrigin != Type::Unknown &&
               record.kind == AggregateKind::Opaque)) {
            target.fields = record.fields;
            target.opaqueBounds = record.opaqueBounds;
          } else if (record.kind == AggregateKind::Array &&
                     record.arrayCount == Type::Unknown) {
            if constexpr (std::is_same_v<T, ImportedProduct>)
              target.fields.resize(record.fields.size());
            else
              target.fields =
                  arena->allocate<BasicTypeField<BorrowedTypeStorage>>(
                      record.fields.size());
          }
          if (source.closure)
            result.closure.emplace();
          result.coroutineInterior = source.coroutineInterior;
          return result;
        } else if constexpr (std::is_same_v<T, TypeParameter> ||
                             std::is_same_v<T, CompactParameter>) {
          T result;
          result.kind = source.kind;
          result.valueType = source.valueType;
          result.numeric = source.numeric;
          result.operands = source.operands;
          result.operation = source.operation;
          result.value = source.value;
          result.copyRequested = source.copyRequested;
          result.sized = source.sized;
          result.thin = source.thin;
          result.regionArguments = source.regionArguments;
          return result;
        } else {
          auto result = source;
          if constexpr (std::is_same_v<T, ImportedPointer> ||
                        std::is_same_v<T, CompactPointer>)
            result.descriptor.name = {};
          else
            result.name = {};
          if constexpr (std::is_same_v<T, ErasedType> ||
                        std::is_same_v<T, CompactErased>) {
            result.methods = {};
            result.methodTypes = {};
            result.methodOwners = {};
            result.methodSlots = {};
            result.parentInterfaces = {};
          } else if constexpr (std::is_same_v<T, CallableType> ||
                               std::is_same_v<T, CompactCallable>) {
            if constexpr (std::is_same_v<T, CompactCallable>) {
              auto parameters =
                  arena->allocate<BasicCallableParameter<BorrowedTypeStorage>>(
                      source.parameters.size());
              std::copy(source.parameters.begin(), source.parameters.end(),
                        parameters.begin());
              result.parameters = parameters;
              result.regions =
                  arena->allocate<std::string_view>(source.regions.size());
            }
            for (auto &parameter : result.parameters)
              parameter.name = {};
            for (auto &region : result.regions)
              region = {};
          }
          return result;
        }
      },
      value);
}

template <class Decoder, class Definition>
std::span<const std::uint8_t> framedDefinition(Decoder &reader,
                                               Definition &definition) {
  auto payload = reader.block();
  auto end = reader.offset;
  auto bytes = reader.bytes;
  reader.bytes = payload;
  reader.offset = 0;
  std::visit([&](auto &record) { reader(record); }, definition);
  if (reader.remaining())
    reject("trailing bytes in an indexed type record");
  reader.bytes = bytes;
  reader.offset = end;
  return payload;
}
struct LookupReferences {
  std::function<std::optional<std::uint32_t>(Type)> type;
  std::function<std::optional<std::uint32_t>(RegionId)> region;
  std::function<std::optional<std::uint32_t>(RegionUniverse)> universe;
  std::function<std::optional<std::string_view>(std::uint32_t)> interface;
};
template <class Sink>
bool writeLookupKey(Sink &writer, const ImportedTypeQuery &query,
                    const LookupReferences &references) {
  writer.byte(static_cast<std::uint8_t>(query.kind));
  bool valid = true;
  auto ref = [&](auto value, const auto &map) {
    auto encoded = map(value);
    if (encoded)
      writer.u32(*encoded);
    else
      valid = false;
  };
  auto type = [&](Type value) { ref(value, references.type); };
  auto region = [&](RegionId value) { ref(value, references.region); };
  auto types = [&](std::span<const Type> values) {
    writer.u32(static_cast<std::uint32_t>(values.size()));
    for (auto value : values)
      type(value);
  };
  auto regions = [&](std::span<const RegionId> values) {
    writer.u32(static_cast<std::uint32_t>(values.size()));
    for (auto value : values)
      region(value);
  };
  using Kind = ImportedTypeQuery::Kind;
  const auto &key = query.key;
  switch (query.kind) {
  case Kind::Generic:
  case Kind::Regional:
  case Kind::Slice:
    type(key.payload);
    break;
  case Kind::Aggregate:
    writer.byte(static_cast<std::uint8_t>(key.aggregateKind));
    types(key.key);
    break;
  case Kind::Operand:
    types(key.key);
    break;
  case Kind::View:
    type(key.payload);
    writer.byte(static_cast<std::uint8_t>(key.mode));
    region(key.region);
    break;
  case Kind::Pointer:
    type(key.payload);
    writer.byte(static_cast<std::uint8_t>(key.mode));
    break;
  case Kind::GenericExact:
    type(key.payload);
    types(key.key);
    break;
  case Kind::Erased:
  case Kind::ErasedExact:
    if (auto name = references.interface(key.declaration))
      writer.value(*name);
    else
      valid = false;
    if (query.kind == Kind::ErasedExact) {
      types(key.key);
      writer.u32(static_cast<std::uint32_t>(key.associated.size()));
      for (auto binding : key.associated) {
        type(binding.parameter);
        type(binding.argument);
      }
      regions(key.regionArguments);
      region(key.region);
      ref(key.regionUniverse, references.universe);
      regions(key.callableRegionParameters);
      writer.u32(
          static_cast<std::uint32_t>(key.callableRegionRequirements.size()));
      for (auto requirement : key.callableRegionRequirements) {
        region(requirement.longer);
        region(requirement.shorter);
      }
    }
    break;
  case Kind::Callable:
    ref(key.regionUniverse, references.universe);
    regions(key.callableRegionParameters);
    regions(key.callableParameterRegions);
    writer.u32(
        static_cast<std::uint32_t>(key.callableRegionRequirements.size()));
    for (auto requirement : key.callableRegionRequirements) {
      region(requirement.longer);
      region(requirement.shorter);
    }
    types(key.key);
    break;
  case Kind::Constant:
    type(key.valueType);
    writer.u64(key.magnitude[0]);
    writer.u64(key.magnitude[1]);
    break;
  case Kind::NamedProduct:
    writer.value(query.name);
    break;
  }
  return valid;
}
std::optional<std::vector<std::uint8_t>>
lookupKey(const ImportedTypeQuery &query, const LookupReferences &references) {
  Writer writer;
  if (!writeLookupKey(writer, query, references))
    return {};
  return std::move(writer.bytes);
}
template <class Visit>
void lookupQueries(ImportedTypeKind kind, const ImportedTypeIndex &index,
                   std::string_view name, Visit visit) {
  using Kind = ImportedTypeQuery::Kind;
  auto emit = [&](Kind kind) { visit(ImportedTypeQuery{kind, index}); };
  switch (kind) {
  case ImportedTypeKind::Product: {
    ImportedTypeQuery named{Kind::NamedProduct, index};
    named.name = name;
    visit(named);
  }
    if (index.genericOrigin != Type::Unknown) {
      auto key = index;
      key.payload = index.genericOrigin;
      visit(ImportedTypeQuery{Kind::Generic, key});
      key.key = index.genericArguments;
      visit(ImportedTypeQuery{Kind::GenericExact, key});
    }
    if (index.regionOrigin != Type::Unknown) {
      auto key = index;
      key.payload = index.regionOrigin;
      visit(ImportedTypeQuery{Kind::Regional, key});
    }
    emit(Kind::Aggregate);
    break;
  case ImportedTypeKind::View:
    emit(Kind::View);
    break;
  case ImportedTypeKind::Pointer:
    emit(Kind::Pointer);
    break;
  case ImportedTypeKind::Slice:
    emit(Kind::Slice);
    break;
  case ImportedTypeKind::Parameter:
    emit(index.parameterKind == TypeParameterKind::Value ? Kind::Constant
                                                         : Kind::Operand);
    break;
  case ImportedTypeKind::Callable:
    emit(Kind::Callable);
    break;
  case ImportedTypeKind::Erased:
    emit(Kind::Erased);
    emit(Kind::ErasedExact);
    break;
  }
}
std::uint32_t wireU32(std::span<const std::uint8_t> bytes, std::size_t offset) {
  if (offset > bytes.size() || bytes.size() - offset < 4)
    reject("truncated type lookup index");
  std::uint32_t value = 0;
  for (unsigned i = 0; i < 4; ++i)
    value |= static_cast<std::uint32_t>(bytes[offset + i]) << (8 * i);
  return value;
}
struct LookupKeyMatch {
  std::span<const std::uint8_t> bytes;
  std::size_t offset = 0;
  bool matched = true;
  void byte(std::uint8_t value) {
    if (offset == bytes.size() || bytes[offset] != value)
      matched = false;
    if (offset != bytes.size())
      ++offset;
  }
  void u32(std::uint32_t value) {
    if (bytes.size() - offset < 4) {
      matched = false;
      offset = bytes.size();
      return;
    }
    matched &= wireU32(bytes, offset) == value;
    offset += 4;
  }
  void u64(std::uint64_t value) {
    u32(static_cast<std::uint32_t>(value));
    u32(static_cast<std::uint32_t>(value >> 32));
  }
  void value(std::string_view text) {
    u32(static_cast<std::uint32_t>(text.size()));
    if (text.size() > bytes.size() - offset) {
      matched = false;
      offset = bytes.size();
      return;
    }
    matched &= std::equal(text.begin(), text.end(), bytes.begin() + offset,
                          [](char left, std::uint8_t right) {
                            return static_cast<std::uint8_t>(left) == right;
                          });
    offset += text.size();
  }
  bool exact() const { return matched && offset == bytes.size(); }
};
struct WireTypeLookup {
  struct Admission {
    std::vector<std::size_t> offsets;
    std::vector<std::uint32_t> groups;
  };
  struct Group {
    std::span<const std::uint8_t> key, ordinals;
  };
  std::span<const std::uint8_t> bytes;
  std::uint32_t count = 0;
  std::size_t membershipCount = 0;

  std::size_t directorySize() const {
    return 4 + (static_cast<std::size_t>(count) + 1) * 4;
  }
  Group group(std::size_t ordinal) const {
    auto begin = wireU32(bytes, 4 + ordinal * 4);
    auto end = wireU32(bytes, 8 + ordinal * 4);
    auto record = bytes.subspan(directorySize() + begin, end - begin);
    auto keySize = wireU32(record, 0);
    if (keySize > record.size() - 4)
      reject("truncated type lookup key");
    auto key = record.subspan(4, keySize);
    auto candidateCount = wireU32(record, 4 + keySize);
    if (candidateCount != (record.size() - 8 - keySize) / 4 ||
        (record.size() - 8 - keySize) % 4)
      reject("invalid type lookup candidate count");
    return {key, record.subspan(8 + keySize)};
  }
  void validate(std::uint32_t typeCount, Admission *admission = nullptr) {
    count = wireU32(bytes, 0);
    if (count > bytes.size() / 4 || directorySize() > bytes.size() ||
        wireU32(bytes, 4) != 0 ||
        wireU32(bytes, 4 + static_cast<std::size_t>(count) * 4) !=
            bytes.size() - directorySize())
      reject("invalid type lookup directory");
    std::span<const std::uint8_t> previous;
    membershipCount = 0;
    if (admission)
      admission->offsets.assign(static_cast<std::size_t>(typeCount) + 1, 0);
    for (std::size_t i = 0; i < count; ++i) {
      auto begin = wireU32(bytes, 4 + i * 4);
      auto end = wireU32(bytes, 8 + i * 4);
      if (end < begin || end > bytes.size() - directorySize() ||
          end - begin < 8)
        reject("invalid type lookup group range");
      auto current = group(i);
      if (current.key.empty() || current.ordinals.empty() ||
          (i && !std::lexicographical_compare(previous.begin(), previous.end(),
                                              current.key.begin(),
                                              current.key.end())))
        reject("unordered or empty type lookup group");
      std::uint32_t last = 0;
      for (std::size_t j = 0; j < current.ordinals.size(); j += 4) {
        auto value = wireU32(current.ordinals, j);
        if (value >= typeCount || (j && value <= last))
          reject("invalid type lookup candidate");
        last = value;
        ++membershipCount;
        if (admission)
          ++admission->offsets[value + 1];
      }
      previous = current.key;
    }
    if (admission) {
      for (std::size_t i = 1; i < admission->offsets.size(); ++i)
        admission->offsets[i] += admission->offsets[i - 1];
      admission->groups.resize(membershipCount);
      auto positions = admission->offsets;
      for (std::uint32_t i = 0; i < count; ++i) {
        auto current = group(i);
        for (std::size_t j = 0; j < current.ordinals.size(); j += 4)
          admission->groups[positions[wireU32(current.ordinals, j)]++] = i;
      }
    }
  }
  std::span<const std::uint8_t> find(std::span<const std::uint8_t> key) const {
    std::size_t first = 0, last = count;
    while (first != last) {
      auto middle = first + (last - first) / 2;
      auto current = group(middle);
      if (std::lexicographical_compare(current.key.begin(), current.key.end(),
                                       key.begin(), key.end()))
        first = middle + 1;
      else
        last = middle;
    }
    if (first == count)
      return {};
    auto current = group(first);
    return std::equal(key.begin(), key.end(), current.key.begin(),
                      current.key.end())
               ? current.ordinals
               : std::span<const std::uint8_t>{};
  }
};
void writeLookupTable(Writer &body, Graph &graph,
                      const TypeGraphSymbols &symbols);
} // namespace

TypeGraphExport exportTypeGraph(const TypeStore &types,
                                std::span<const Type> roots,
                                const TypeGraphSymbols &symbols,
                                ValidationMode validation) {
  try {
    if (roots.size() > limits::sourceBytes / 4)
      reject("type graph root table exceeds source byte limit");
    if (types.targetPointerBits() != 16 && types.targetPointerBits() != 32 &&
        types.targetPointerBits() != 64)
      reject("invalid type graph target pointer width");
    Graph graph(types);
    for (auto type : roots)
      graph.type(type);
    Writer body(graph, symbols);
    std::set<DefinitionIdentity> identities;
    for (std::size_t i = 0; i < graph.typeList.size(); ++i) {
      auto type = graph.typeList[i];
      auto definition = types.importedDefinition(type);
      std::optional<DefinitionIdentity> identity;
      if (nominal(definition)) {
        if (!symbols.definition || !(identity = symbols.definition(type)))
          reject("missing logical type definition identity");
        validIdentity(*identity,
                      std::holds_alternative<TypeParameter>(definition));
        if (!identities.insert(*identity).second)
          reject("duplicate logical definition identity");
      }
      body(identity);
      if (validation != ValidationMode::Eager) {
        auto writeRecord = [&](const ImportedTypeDefinition &record) {
          Writer framed(graph, symbols);
          std::visit([&](const auto &value) { framed(value); }, record);
          if (framed.bytes.size() > limits::sourceBytes)
            reject("indexed type record exceeds source byte limit");
          body.u32(static_cast<std::uint32_t>(framed.bytes.size()));
          body.bytes.insert(body.bytes.end(), framed.bytes.begin(),
                            framed.bytes.end());
        };
        writeRecord(identityDefinition(definition));
        writeRecord(definition);
      } else
        std::visit([&](auto &r) { body(r); }, definition);
    }
    std::vector<WireRegion> regionRecords;
    for (std::size_t i = 0; i < graph.regionList.size(); ++i) {
      auto r = types.regions().get(graph.regionList[i]);
      WireRegion wire;
      wire.kind = r.kind;
      wire.name = r.name;
      if (r.kind != RegionKind::Intersection) {
        wire.binder = graph.binder(r.binder, r.universe);
        wire.universe = graph.universe(r.universe);
      }
      for (auto source : r.sources)
        wire.sources.push_back(graph.region(source));
      regionRecords.push_back(std::move(wire));
    }
    Writer out(graph, symbols);
    for (auto byte : magic)
      out.byte(byte);
    out.u32(validation != ValidationMode::Eager ? indexedVersion : version);
    out.u32(types.targetPointerBits());
    out.u32(static_cast<std::uint32_t>(graph.typeList.size()));
    out.u32(static_cast<std::uint32_t>(graph.regionList.size()));
    out.u32(static_cast<std::uint32_t>(graph.universes.size()));
    out.u32(static_cast<std::uint32_t>(graph.binders.size()));
    out.u32(static_cast<std::uint32_t>(roots.size()));
    for (auto type : graph.typeList) {
      auto kind = types.importedKind(type);
      out(kind);
    }
    for (auto universe : graph.universes)
      out.u32(graph.universe(types.regions().universeParent(universe)));
    for (auto universe : graph.binderUniverses)
      out.u32(graph.universe(universe));
    for (auto &region : regionRecords)
      record(out, region);
    if (validation != ValidationMode::Eager)
      writeLookupTable(out, graph, symbols);
    for (auto byte : body.bytes)
      out.byte(byte);
    for (auto root : roots)
      out.u32(graph.type(root));
    return {std::move(out.bytes), {}};
  } catch (const InvalidGraph &error) {
    return {{}, error.message};
  }
}

static TypeGraphImport importTypeGraphEager(TypeStore &types,
                                            std::span<const std::uint8_t> bytes,
                                            const TypeGraphSymbols &symbols) {
  try {
    Header header;
    Reader reader(bytes, symbols, header);
    readHeader(reader, header, types.targetPointerBits());
    Tables tables;
    readTables(reader, tables);
    if (header.indexed) {
      WireTypeLookup lookup{reader.block()};
      lookup.validate(header.types);
    }
    auto minimumBytes = static_cast<std::size_t>(header.roots) * 4;
    if (minimumBytes > reader.remaining())
      reject("truncated type graph roots");
    for (auto kind : tables.kinds) {
      const auto required = minimumDefinitionBytes(kind);
      if (required > reader.remaining() - minimumBytes)
        reject("truncated type graph definitions");
      minimumBytes += required;
    }
    TypeStore candidate = types;
    std::vector<RegionId> regions;
    std::vector<RegionUniverse> universes;
    importRegions(candidate, tables, regions, universes);
    auto localTypes = builtinTypes();
    localTypes.reserve(localTypes.size() + tables.kinds.size());
    const bool fresh = types.storedTypeCount() == 0;
    for (auto kind : tables.kinds)
      localTypes.push_back(candidate.declareImportedType(kind));
    reader.types = localTypes;
    reader.regions = regions;
    reader.universes = universes;
    auto decodedIds = std::span(localTypes).subspan(primitiveCount);
    std::vector<std::optional<DefinitionIdentity>> logical;
    logical.reserve(header.types);
    TypeGraphImport result;
    result.definitions.reserve(header.types);
    result.roots.reserve(header.roots);
    std::unordered_set<std::string_view> identities;
    for (std::uint32_t i = 0; i < header.types; ++i) {
      const auto identityBegin = reader.offset;
      std::optional<DefinitionIdentity> identity;
      reader(identity);
      const auto identityBytes =
          bytes.subspan(identityBegin, reader.offset - identityBegin);
      auto definition = definitionFor(tables.kinds[i]);
      if (header.indexed) {
        reader.block();
        framedDefinition(reader, definition);
      } else
        std::visit([&](auto &r) { reader(r); }, definition);
      if (nominal(definition) != identity.has_value())
        reject("missing or unexpected logical definition identity");
      if (identity) {
        validIdentity(*identity,
                      std::holds_alternative<TypeParameter>(definition));
        if (!identities
                 .insert({reinterpret_cast<const char *>(identityBytes.data()),
                          identityBytes.size()})
                 .second)
          reject("duplicate logical definition identity");
      }
      logical.push_back(std::move(identity));
      candidate.defineImportedType(decodedIds[i], std::move(definition));
    }
    DecodedDefinitions staged(candidate, decodedIds);
    for (std::uint32_t i = 0; i < header.roots; ++i) {
      Type root;
      reader(root);
      result.roots.push_back(root);
    }
    if (reader.remaining())
      reject("trailing bytes in type graph");
    const auto resolvedSymbols = reader.resolveSymbols();
    auto symbolsOf = [&](SymbolKind kind) -> std::span<const std::uint32_t> {
      return resolvedSymbols[static_cast<std::size_t>(kind)];
    };
    candidate.remapImportedSymbols(
        decodedIds,
        {symbolsOf(SymbolKind::Function), symbolsOf(SymbolKind::Closure),
         symbolsOf(SymbolKind::Interface), symbolsOf(SymbolKind::Package)});
    validateGraph(candidate, decodedIds, staged);
    bool uniqueKeys = false;
    if (fresh && !symbols.lookupDefinition)
      recursiveRegionals(decodedIds, staged, &uniqueKeys);
    if (uniqueKeys) {
      // Unique raw keys in the acyclic identity graph need no remapping.
      for (std::size_t i = 0; i < staged.size(); ++i) {
        if (logical[i])
          result.definitions.push_back({*logical[i], decodedIds[i]});
      }
      types = std::move(candidate);
      return result;
    }
    std::vector<ImportedTypeDefinition> definitions;
    definitions.reserve(staged.size());
    for (std::size_t i = 0; i < staged.size(); ++i)
      definitions.push_back(candidate.importedDefinition(decodedIds[i]));
    TypeStore decoded = std::move(candidate);
    auto existing = matchExisting(decoded, types, decodedIds, logical, symbols);
    candidate = types;
    remapRegionGraph(candidate, decoded, tables, regions, universes, existing,
                     definitions);
    CanonicalImport canonical(types, candidate, decoded, decodedIds,
                              definitions, logical, existing);
    canonical.finish();
    for (std::size_t i = 0; i < logical.size(); ++i)
      if (logical[i])
        result.definitions.push_back(
            {*logical[i], canonical.build(decodedIds[i])});
    for (auto &root : result.roots)
      root = canonical.build(root);
    types = std::move(candidate);
    return result;
  } catch (const InvalidGraph &error) {
    return {{}, {}, error.message};
  }
}

namespace {
struct DeferredTypeGraph {
  struct Record {
    std::size_t offset = 0, length = 0;
    std::size_t projectionOffset = 0, projectionLength = 0;
    bool nominal = false;
  };
  Header header;
  std::shared_ptr<const void> backing;
  std::span<const std::uint8_t> bytes;
  std::vector<ImportedTypeKind> kinds;
  std::vector<Type> types;
  std::vector<RegionId> regions;
  std::vector<RegionUniverse> universes;
  Reader::ResolvedSymbols symbols;
  std::vector<Record> records;
  mutable std::vector<ImportedTypeScalars> scalars;
  bool queryValidation = false;
  mutable std::unordered_map<std::size_t,
                             std::vector<std::vector<std::uint8_t>>>
      projectedKeys;
  mutable std::unordered_map<std::size_t,
                             std::array<std::vector<std::size_t>, 2>>
      projectionEdges;
  mutable std::unordered_set<std::size_t> projectionProofs;
  mutable std::unordered_map<std::string, std::size_t> projectionIdentities;
  mutable std::mutex projectionMutex, symbolMutex;
  std::shared_ptr<const CompactArena> arena;
  std::vector<CompactDefinitionView> definitions;
  mutable std::unordered_map<std::size_t, CompactDefinitionView>
      demandedDefinitions;
  std::shared_ptr<const TypeGraphSymbols> retainedSymbols;
  std::optional<RegionStore> validationRegions;
  VaListAbi validationAbi{};
  std::vector<ImportedTypeIndex> index;
  WireTypeLookup lookup;
  LookupReferences references;
  std::map<std::uint32_t, std::uint32_t> regionOrdinals, universeOrdinals;
  mutable std::map<std::uint32_t, std::vector<std::string_view>> interfaces;
  mutable bool interfaceNamesReady = false;
  mutable std::array<std::unordered_map<std::string_view, std::uint32_t>,
                     Reader::symbolKinds>
      symbolValues;
  mutable std::map<std::vector<std::uint8_t>, std::vector<std::uint32_t>>
      candidates;
  mutable std::mutex lookupMutex;
  mutable std::unordered_set<std::size_t> visiting;
  mutable std::unordered_map<std::size_t, TypeGraphProof> validated;
  std::shared_ptr<CompactArena> demandedArena;
  mutable std::mutex validationMutex;

  void validate(std::size_t index) const;
  ImportedTypeScalars
  project(std::size_t index,
          std::span<const std::uint8_t> requested = {}) const;
  TypeGraphSymbols resolver() const {
    TypeGraphSymbols result;
    result.resolve =
        [this](SymbolKind kind,
               std::string_view name) -> std::optional<std::uint32_t> {
      std::lock_guard lock(symbolMutex);
      auto &values = symbolValues[static_cast<std::size_t>(kind)];
      if (auto found = values.find(name); found != values.end())
        return found->second;
      auto resolved = retainedSymbols->resolve
                          ? retainedSymbols->resolve(kind, name)
                          : std::nullopt;
      if (resolved)
        values.emplace(name, *resolved);
      return resolved;
    };
    return result;
  }
  std::span<const std::uint32_t> resolve(const ImportedTypeQuery &query) const;
  ImportedTypeDefinition materialize(std::size_t index) const {
    validate(index);
    std::lock_guard lock(validationMutex);
    const auto &definition =
        retainedSymbols ? demandedDefinitions.at(index) : definitions.at(index);
    return std::visit(
        [](const auto *record) -> ImportedTypeDefinition {
          return ownCompact(*record);
        },
        definition);
  }
};

void remapCompactSymbols(std::span<CompactDefinitionView> definitions,
                         const Reader::ResolvedSymbols &symbols) {
  auto function = [&](int &value, SymbolKind kind) {
    if (value >= 0)
      value = static_cast<int>(symbols[static_cast<std::size_t>(kind)].at(
          static_cast<std::size_t>(value)));
  };
  for (auto &definition : definitions)
    std::visit(
        [&](auto *value) {
          auto &record = *value;
          using T = std::decay_t<decltype(record)>;
          if constexpr (std::is_same_v<T, CompactProduct>) {
            function(record.descriptor.destructor, SymbolKind::Function);
            auto &package = record.descriptor.package;
            if (package != unknownPackage)
              package =
                  symbols[static_cast<std::size_t>(SymbolKind::Package)].at(
                      package);
            if (record.closure)
              function(record.closure->function, SymbolKind::Closure);
          } else if constexpr (std::is_same_v<T, CompactCallable>)
            function(record.function, SymbolKind::Closure);
          else if constexpr (std::is_same_v<T, CompactErased>) {
            record.declaration =
                symbols[static_cast<std::size_t>(SymbolKind::Interface)].at(
                    record.declaration);
            for (auto &method : record.methods)
              function(method.function, SymbolKind::Closure);
          }
        },
        definition);
}

template <class Definition>
ImportedTypeIndex compactIndex(const Definition &definition,
                               CompactArena &arena) {
  ImportedTypeIndex result;
  visitDefinition(
      [&](const auto &record) {
        using T = std::decay_t<decltype(record)>;
        if constexpr (std::is_same_v<T, CompactProduct> ||
                      std::is_same_v<T, ImportedProduct>) {
          result.aggregateKind = record.descriptor.kind;
          result.genericOrigin = record.descriptor.genericOrigin;
          result.regionOrigin = record.descriptor.regionOrigin;
          result.key = record.descriptor.components;
          result.genericArguments = record.descriptor.genericArguments;
          result.closure = record.closure.has_value();
          result.coroutineInterior = record.coroutineInterior;
        } else if constexpr (std::is_same_v<T, CompactView> ||
                             std::is_same_v<T, ViewType>) {
          result.payload = record.payload;
          result.mode = record.mode;
          result.region = record.region;
        } else if constexpr (std::is_same_v<T, CompactPointer> ||
                             std::is_same_v<T, ImportedPointer>) {
          result.payload = record.descriptor.payload;
          result.mode = record.descriptor.mode;
        } else if constexpr (std::is_same_v<T, CompactSlice> ||
                             std::is_same_v<T, SliceType>)
          result.payload = record.element;
        else if constexpr (std::is_same_v<T, CompactParameter> ||
                           std::is_same_v<T, TypeParameter>) {
          result.parameterKind = record.kind;
          result.valueType = record.valueType;
          result.magnitude = record.numeric.magnitude;
          result.key = record.operands;
        } else if constexpr (std::is_same_v<T, CompactCallable> ||
                             std::is_same_v<T, CallableType>) {
          auto key = arena.allocate<Type>(record.parameters.size() + 2);
          key[0] = record.result;
          key[1] = record.error;
          for (std::size_t i = 0; i < record.parameters.size(); ++i)
            key[i + 2] = record.parameters[i].type;
          result.key = key;
          result.regionUniverse = record.regionUniverse;
          result.callableRegionParameters = record.regionParameters;
          result.callableParameterRegions = record.parameterRegions;
          result.callableRegionRequirements = record.regionRequirements;
        } else {
          result.declaration = record.declaration;
          result.key = record.arguments;
          result.associated = record.associated;
          result.regionArguments = record.regionArguments;
          result.region = record.bound;
          result.regionUniverse = record.regionUniverse;
          result.callableRegionParameters = record.regionParameters;
          result.callableRegionRequirements = record.regionRequirements;
        }
      },
      definition);
  return result;
}
void writeLookupTable(Writer &body, Graph &graph,
                      const TypeGraphSymbols &symbols) {
  std::map<std::vector<std::uint8_t>, std::vector<std::uint32_t>> groups;
  std::map<std::uint32_t, std::string> interfaces;
  LookupReferences references{
      [&](Type value) -> std::optional<std::uint32_t> {
        return graph.type(value);
      },
      [&](RegionId value) -> std::optional<std::uint32_t> {
        return graph.region(value);
      },
      [&](RegionUniverse value) -> std::optional<std::uint32_t> {
        return graph.universe(value);
      },
      [&](std::uint32_t declaration) -> std::optional<std::string_view> {
        if (auto found = interfaces.find(declaration);
            found != interfaces.end())
          return found->second;
        auto name = symbols.symbol
                        ? symbols.symbol(SymbolKind::Interface, declaration)
                        : std::nullopt;
        if (!name || name->empty())
          return {};
        return interfaces.emplace(declaration, std::move(*name)).first->second;
      }};
  CompactArena arena;
  for (std::size_t i = 0; i < graph.typeList.size(); ++i) {
    auto definition = graph.types.importedDefinition(graph.typeList[i]);
    auto index = compactIndex(definition, arena);
    auto product = definitionRecord<ImportedProduct>(definition);
    lookupQueries(graph.types.importedKind(graph.typeList[i]), index,
                  product ? std::string_view(product->descriptor.name)
                          : std::string_view{},
                  [&](const ImportedTypeQuery &query) {
                    auto key = lookupKey(query, references);
                    if (!key)
                      reject("unmapped exported type lookup key");
                    groups[std::move(*key)].push_back(
                        static_cast<std::uint32_t>(i));
                  });
    arena.reset();
  }
  Writer directory, records;
  directory.u32(static_cast<std::uint32_t>(groups.size()));
  for (const auto &[key, ordinals] : groups) {
    directory.u32(static_cast<std::uint32_t>(records.bytes.size()));
    records.u32(static_cast<std::uint32_t>(key.size()));
    for (auto byte : key)
      records.byte(byte);
    records.u32(static_cast<std::uint32_t>(ordinals.size()));
    for (auto ordinal : ordinals)
      records.u32(ordinal);
  }
  directory.u32(static_cast<std::uint32_t>(records.bytes.size()));
  const auto size = directory.bytes.size() + records.bytes.size();
  if (size > limits::sourceBytes)
    reject("type lookup index exceeds source byte limit");
  body.u32(static_cast<std::uint32_t>(size));
  for (auto byte : directory.bytes)
    body.byte(byte);
  for (auto byte : records.bytes)
    body.byte(byte);
}
std::span<const std::uint32_t>
DeferredTypeGraph::resolve(const ImportedTypeQuery &query) const {
  std::lock_guard lock(lookupMutex);
  auto normalized = references;
  std::vector<std::uint8_t> cacheKey;
  const std::vector<std::string_view> *names = nullptr;
  if (query.kind == ImportedTypeQuery::Kind::Erased ||
      query.kind == ImportedTypeQuery::Kind::ErasedExact) {
    if (queryValidation && !interfaceNamesReady) {
      auto callbacks = resolver();
      decltype(interfaces) mapped;
      for (std::size_t i = 0; i < lookup.count; ++i) {
        auto key = lookup.group(i).key;
        if (key.front() !=
            static_cast<std::uint8_t>(ImportedTypeQuery::Kind::Erased))
          continue;
        if (key.size() < 5)
          throw InvalidMetadata("invalid erased type lookup key");
        auto size = wireU32(key, 1);
        if (key.size() != 5 + std::size_t(size))
          throw InvalidMetadata("invalid erased type lookup key");
        std::string_view name(reinterpret_cast<const char *>(key.data() + 5),
                              size);
        auto declaration = callbacks.resolve(SymbolKind::Interface, name);
        if (!declaration)
          throw InvalidMetadata("unknown erased type lookup interface");
        mapped[*declaration].push_back(name);
      }
      interfaces = std::move(mapped);
      interfaceNamesReady = true;
    }
    auto found = interfaces.find(query.key.declaration);
    if (found == interfaces.end())
      return {};
    names = &found->second;
    Writer writer;
    writer.byte(static_cast<std::uint8_t>(query.kind));
    writer.u32(query.key.declaration);
    cacheKey = std::move(writer.bytes);
    if (query.kind == ImportedTypeQuery::Kind::ErasedExact) {
      normalized.interface = [name = names->front()](std::uint32_t)
          -> std::optional<std::string_view> { return name; };
      auto encoded = lookupKey(query, normalized);
      if (!encoded)
        return {};
      cacheKey.insert(cacheKey.end(), encoded->begin(), encoded->end());
    }
  } else {
    auto encoded = lookupKey(query, references);
    if (!encoded)
      return {};
    cacheKey = std::move(*encoded);
  }
  if (auto found = candidates.find(cacheKey); found != candidates.end())
    return found->second;
  std::vector<std::uint32_t> values;
  auto append = [&](std::span<const std::uint8_t> key) {
    auto ordinals = lookup.find(key);
    for (std::size_t i = 0; i < ordinals.size(); i += 4) {
      auto ordinal = wireU32(ordinals, i);
      if (queryValidation)
        project(ordinal, key);
      values.push_back(ordinal);
    }
  };
  if (names) {
    for (auto name : *names) {
      normalized.interface =
          [name](std::uint32_t) -> std::optional<std::string_view> {
        return name;
      };
      append(*lookupKey(query, normalized));
    }
    std::sort(values.begin(), values.end());
    values.erase(std::unique(values.begin(), values.end()), values.end());
  } else
    append(cacheKey);
  return candidates.emplace(std::move(cacheKey), std::move(values))
      .first->second;
}

ImportedTypeScalars
DeferredTypeGraph::project(std::size_t index,
                           std::span<const std::uint8_t> requested) const {
  std::lock_guard lock(projectionMutex);
  try {
    auto read = [&](std::size_t index) {
      auto found = projectedKeys.find(index);
      if (found == projectedKeys.end()) {
        const auto &slice = records.at(index);
        auto callbacks = resolver();
        CompactReader reader(
            bytes.subspan(slice.projectionOffset, slice.projectionLength),
            callbacks, header);
        reader.types = types;
        reader.regions = regions;
        reader.universes = universes;
        auto definition = compactDefinitionFor(kinds[index]);
        std::visit([&](auto &value) { reader(value); }, definition);
        if (reader.remaining() || nominal(definition) != slice.nominal)
          reject("invalid demanded type projection");
        auto view = std::visit(
            [](auto &record) -> CompactDefinitionView { return &record; },
            definition);
        std::array<CompactDefinitionView, 1> remapped{view};
        auto symbols = reader.resolveSymbols();
        remapCompactSymbols(remapped, symbols);
        auto indexValue = compactIndex(view, *reader.arena);
        auto references = this->references;
        references.interface =
            [&](std::uint32_t declaration) -> std::optional<std::string_view> {
          auto kind = static_cast<std::size_t>(SymbolKind::Interface);
          for (std::size_t i = 0; i < symbols[kind].size(); ++i)
            if (symbols[kind][i] == declaration)
              return reader.pendingSymbols[kind][i];
          return std::nullopt;
        };
        auto product = definitionRecord<ImportedProduct>(view);
        std::vector<std::vector<std::uint8_t>> keys;
        lookupQueries(kinds[index], indexValue,
                      product ? product->descriptor.name : std::string_view{},
                      [&](const ImportedTypeQuery &query) {
                        auto key = lookupKey(query, references);
                        if (!key)
                          reject("unmapped demanded type lookup key");
                        auto ordinals = lookup.find(*key);
                        bool present = false;
                        for (std::size_t i = 0; i < ordinals.size(); i += 4)
                          if (wireU32(ordinals, i) == index) {
                            present = true;
                            break;
                          }
                        if (!present)
                          reject("type lookup index does not match projection");
                        keys.push_back(std::move(*key));
                      });
        auto &facts = scalars[index];
        facts.parameterKind = indexValue.parameterKind;
        facts.valueType = indexValue.valueType;
        facts.declaration = indexValue.declaration;
        facts.payload = indexValue.payload;
        facts.region = indexValue.region;
        facts.genericOrigin = indexValue.genericOrigin;
        facts.regionOrigin = indexValue.regionOrigin;
        if (product)
          facts.aggregateKind = product->descriptor.kind;
        std::array<std::vector<std::size_t>, 2> edges;
        if (!slice.nominal) {
          auto identity = canonicalKey(view);
          auto [previous, inserted] =
              projectionIdentities.emplace(std::move(identity), index);
          if (!inserted && previous->second != index)
            reject("duplicate canonical indexed type");
          std::vector<Type> dependencies;
          canonicalKey(view, &dependencies);
          for (auto type : dependencies)
            if (type.index() >= builtinTypeCount)
              edges[0].push_back(type.index() - builtinTypeCount);
        }
        if (product)
          for (auto origin : {facts.genericOrigin, facts.regionOrigin})
            if (origin != Type::Unknown) {
              if (origin.index() < builtinTypeCount ||
                  kinds[origin.index() - builtinTypeCount] !=
                      ImportedTypeKind::Product)
                reject("invalid product origin");
              edges[1].push_back(origin.index() - builtinTypeCount);
            }
        projectionEdges.emplace(index, std::move(edges));
        projectedKeys.emplace(index, std::move(keys));
      }
    };
    if (!projectionProofs.contains(index)) {
      std::vector<std::size_t> pending{index};
      std::unordered_map<std::size_t, std::size_t> positions{{index, 0}};
      FlatTypeEdges canonical;
      std::vector<std::vector<std::size_t>> origins;
      for (std::size_t next = 0; next < pending.size(); ++next) {
        auto current = pending[next];
        read(current);
        origins.emplace_back();
        const auto &edges = projectionEdges.at(current);
        for (std::size_t kind = 0; kind < edges.size(); ++kind)
          for (auto target : edges[kind]) {
            if (projectionProofs.contains(target))
              continue;
            auto [position, added] = positions.emplace(target, pending.size());
            if (added)
              pending.push_back(target);
            if (kind)
              origins[next].push_back(position->second);
            else
              canonical.targets.push_back(position->second);
          }
        canonical.offsets.push_back(canonical.targets.size());
      }
      acyclic(origins);
      recursiveRegionals(std::move(canonical), [&](std::size_t node) {
        return scalars[pending[node]].regionOrigin != Type::Unknown;
      });
      projectionProofs.insert(pending.begin(), pending.end());
    }
    const auto &keys = projectedKeys.at(index);
    if (!requested.empty() &&
        std::none_of(keys.begin(), keys.end(), [&](const auto &key) {
          return std::equal(key.begin(), key.end(), requested.begin(),
                            requested.end());
        }))
      reject("type lookup index does not match projection");
    return scalars[index];
  } catch (const InvalidGraph &error) {
    throw InvalidMetadata("invalid demanded type projection: " + error.message);
  }
}

void DeferredTypeGraph::validate(std::size_t index) const {
  if (!retainedSymbols)
    return;
  std::lock_guard lock(validationMutex);
  if (validated.contains(index))
    return;
  try {
    std::vector<std::size_t> pending;
    struct ResetVisiting {
      std::unordered_set<std::size_t> &visiting;
      const std::vector<std::size_t> &pending;
      ~ResetVisiting() {
        for (auto index : pending)
          visiting.erase(index);
      }
    } reset{visiting, pending};
    auto require = [&](Type type) {
      if (type.index() < builtinTypeCount)
        return;
      auto current = static_cast<std::size_t>(type.index() - builtinTypeCount);
      if (validated.contains(current))
        return;
      if (visiting.insert(current).second) {
        pending.push_back(current);
      }
      if (!demandedDefinitions.contains(current)) {
        if (queryValidation)
          project(current);
        const auto &slice = records[current];
        auto callbacks = resolver();
        CompactReader reader(
            std::span(bytes).subspan(slice.offset, slice.length), callbacks,
            header, demandedArena);
        reader.types = types;
        reader.regions = regions;
        reader.universes = universes;
        auto definition = compactDefinitionFor(kinds[current]);
        std::visit([&](auto &value) { reader(value); }, definition);
        if (reader.remaining())
          reject("trailing bytes in a demanded type record");
        auto value = std::visit(
            [&](auto &record) -> CompactDefinitionView {
              using T = std::decay_t<decltype(record)>;
              auto storage = reader.arena->allocate<T>(1);
              storage.front() = std::move(record);
              return &storage.front();
            },
            definition);
        auto resolved = reader.resolveSymbols();
        std::array<CompactDefinitionView, 1> remapped{value};
        remapCompactSymbols(remapped, resolved);
        CompactReader projection(
            std::span(bytes).subspan(slice.projectionOffset,
                                     slice.projectionLength),
            callbacks, header);
        projection.types = types;
        projection.regions = regions;
        projection.universes = universes;
        auto projected = compactDefinitionFor(kinds[current]);
        std::visit([&](auto &value) { projection(value); }, projected);
        auto expectedDefinition = std::visit(
            [](auto &record) -> CompactDefinitionView { return &record; },
            projected);
        std::array<CompactDefinitionView, 1> expectedRemap{expectedDefinition};
        remapCompactSymbols(expectedRemap, projection.resolveSymbols());
        auto actualProjection =
            identityDefinition(value, projection.arena.get());
        Writer expected, actual;
        visitDefinition([&](const auto &record) { expected(record); },
                        projected);
        visitDefinition([&](const auto &record) { actual(record); },
                        actualProjection);
        if (slice.nominal != nominal(value) || expected.bytes != actual.bytes)
          reject("type record does not match its identity index");
        demandedDefinitions.emplace(current, value);
      }
    };
    require(types[primitiveCount + index]);
    CompactDefinitions available{demandedDefinitions, kinds};
    validateGraph(CompactTypes{*validationRegions, header.pointerBits,
                               validationAbi, available, require},
                  std::span(types).subspan(primitiveCount), available, &pending,
                  &validated);
  } catch (const InvalidGraph &error) {
    throw InvalidMetadata("invalid demanded type record: " + error.message);
  }
}

TypeGraphImport
importCompactTypeGraph(TypeStore &types, std::span<const std::uint8_t> bytes,
                       const TypeGraphSymbols &symbols,
                       ValidationMode validation,
                       std::shared_ptr<const TypeGraphSymbols> retainedSymbols,
                       std::shared_ptr<const void> backing) {
  try {
    auto deferred = std::make_shared<DeferredTypeGraph>();
    auto &header = deferred->header;
    CompactReader reader(bytes, symbols, header);
    readHeader(reader, header, types.targetPointerBits());
    if (validation == ValidationMode::OnUse && !header.indexed)
      reject("query-driven types require an indexed graph");
    const bool demand = header.indexed && validation != ValidationMode::Eager;
    const bool onUse = validation == ValidationMode::OnUse;
    deferred->queryValidation = onUse;
    Tables tables;
    readTables(reader, tables);
    WireTypeLookup::Admission admission;
    if (header.indexed) {
      deferred->lookup.bytes = reader.block();
      deferred->lookup.validate(header.types,
                                demand && !onUse ? &admission : nullptr);
    }
    auto minimumBytes = static_cast<std::size_t>(header.roots) * 4;
    if (minimumBytes > reader.remaining())
      reject("truncated type graph roots");
    for (auto kind : tables.kinds) {
      auto required = minimumDefinitionBytes(kind);
      if (required > reader.remaining() - minimumBytes)
        reject("truncated type graph definitions");
      minimumBytes += required;
    }
    if (!backing) {
      auto owned = std::make_shared<const std::vector<std::uint8_t>>(
          bytes.begin(), bytes.end());
      bytes = *owned;
      backing = std::move(owned);
    }
    deferred->backing = std::move(backing);
    deferred->bytes = bytes;
    if (header.indexed) {
      auto offset = static_cast<std::size_t>(deferred->lookup.bytes.data() -
                                             reader.bytes.data());
      deferred->lookup.bytes =
          bytes.subspan(offset, deferred->lookup.bytes.size());
    }
    reader.bytes = deferred->bytes;
    TypeStore candidate = types;
    importRegions(candidate, tables, deferred->regions, deferred->universes);
    deferred->kinds = std::move(tables.kinds);
    if (demand)
      candidate.reserveImportedTypes(deferred->kinds, deferred);
    deferred->types = builtinTypes();
    deferred->types.reserve(primitiveCount + deferred->kinds.size());
    for (std::size_t i = 0; i < deferred->kinds.size(); ++i)
      deferred->types.push_back(
          demand ? candidate.typeAt(builtinTypeCount + i)
                 : candidate.declareImportedType(deferred->kinds[i]));
    reader.types = deferred->types;
    reader.regions = deferred->regions;
    reader.universes = deferred->universes;
    auto ids = std::span(deferred->types).subspan(primitiveCount);
    std::vector<CompactDefinitionView> definitions;
    if (!demand)
      definitions.reserve(header.types);
    deferred->records.reserve(header.types);
    TypeGraphImport result;
    std::unordered_set<std::string_view> identities;
    bool uniqueKeys = true;
    std::size_t memberships = 0;
    FlatTypeEdges edges;
    std::vector<std::uint8_t> regional, hasIdentity;
    std::vector<std::uint64_t> admittedFingerprints;
    struct SymbolicKey {
      std::uint32_t ordinal;
      std::vector<std::uint8_t> bytes;
      std::vector<Writer::SymbolFixup> symbols;
    };
    std::vector<SymbolicKey> symbolicKeys;
    if (demand && !onUse) {
      edges.offsets.reserve(ids.size() + 1);
      regional.resize(ids.size());
      hasIdentity.resize(ids.size());
      admittedFingerprints.resize(ids.size());
    }
    if (demand) {
      for (std::size_t i = 0; i < deferred->regions.size(); ++i)
        deferred->regionOrdinals.emplace(deferred->regions[i].index(),
                                         static_cast<std::uint32_t>(i));
      for (std::size_t i = 0; i < deferred->universes.size(); ++i)
        deferred->universeOrdinals.emplace(deferred->universes[i],
                                           static_cast<std::uint32_t>(i));
      auto *graph = deferred.get();
      deferred->references = {
          [graph](Type value) -> std::optional<std::uint32_t> {
            if (value.index() < builtinTypeCount) {
              auto found = std::find(primitiveTypes.begin(),
                                     primitiveTypes.end(), value);
              if (found != primitiveTypes.end())
                return static_cast<std::uint32_t>(found -
                                                  primitiveTypes.begin());
            } else if (value.index() - builtinTypeCount < graph->kinds.size())
              return primitiveCount + value.index() - builtinTypeCount;
            return {};
          },
          [graph](RegionId value) -> std::optional<std::uint32_t> {
            auto found = graph->regionOrdinals.find(value.index());
            if (found == graph->regionOrdinals.end())
              return {};
            return found->second;
          },
          [graph](RegionUniverse value) -> std::optional<std::uint32_t> {
            auto found = graph->universeOrdinals.find(value);
            if (found == graph->universeOrdinals.end())
              return {};
            return found->second;
          },
          [](std::uint32_t) -> std::optional<std::string_view> { return {}; }};
    }
    for (std::uint32_t i = 0; i < header.types; ++i) {
      const auto identityBegin = reader.offset;
      std::optional<DefinitionIdentity> identity;
      reader(identity);
      const auto identityBytes =
          bytes.subspan(identityBegin, reader.offset - identityBegin);
      DeferredTypeGraph::Record slice;
      slice.offset = reader.offset;
      std::optional<CompactDefinition> definition;
      if (!onUse)
        definition.emplace(compactDefinitionFor(deferred->kinds[i]));
      if (header.indexed) {
        std::span<const std::uint8_t> payload;
        if (demand) {
          auto projection = reader.block();
          slice.projectionOffset =
              static_cast<std::size_t>(projection.data() - bytes.data());
          slice.projectionLength = projection.size();
          payload = reader.block();
        } else {
          reader.block();
          payload = framedDefinition(reader, *definition);
        }
        slice.offset =
            static_cast<std::size_t>(payload.data() - reader.bytes.data());
        slice.length = payload.size();
      } else {
        std::visit([&](auto &record) { reader(record); }, *definition);
        slice.length = reader.offset - slice.offset;
      }
      slice.nominal = onUse ? identity.has_value() : nominal(*definition);
      deferred->records.push_back(slice);
      if (!demand && slice.nominal != identity.has_value())
        reject("missing or unexpected logical definition identity");
      if (identity) {
        validIdentity(*identity,
                      deferred->kinds[i] == ImportedTypeKind::Parameter);
        if (!identities
                 .insert({reinterpret_cast<const char *>(identityBytes.data()),
                          identityBytes.size()})
                 .second)
          reject("duplicate logical definition identity");
        result.definitions.push_back({std::move(*identity), ids[i]});
      }
      if (demand && !onUse) {
        hasIdentity[i] = identity.has_value();
      } else if (!demand)
        definitions.push_back(std::visit(
            [&](auto &record) -> CompactDefinitionView {
              using T = std::decay_t<decltype(record)>;
              auto storage = reader.arena->allocate<T>(1);
              storage.front() = std::move(record);
              return &storage.front();
            },
            *definition));
    }
    result.roots.reserve(header.roots);
    for (std::uint32_t i = 0; i < header.roots; ++i) {
      Type root;
      reader(root);
      result.roots.push_back(root);
    }
    if (reader.remaining())
      reject("trailing bytes in type graph");
    if (demand && !onUse) {
      struct Projections {
        std::array<std::vector<std::string_view>, Reader::symbolKinds> symbols;
        FlatTypeEdges edges;
        std::vector<SymbolicKey> symbolic;
        std::size_t memberships = 0;
        std::exception_ptr exception;
      };
      const auto count = ids.size();
      deferred->scalars.resize(count);
      const std::size_t workers =
          count < 64 ? 1
                     : std::max<std::size_t>(
                           1, std::min<std::size_t>(
                                  {8, std::thread::hardware_concurrency(),
                                   count / 64 + 1}));
      std::vector<Projections> projections(workers);
      std::vector<std::string> failures(count);
      auto validate = [&](std::size_t worker) {
        try {
          auto &result = projections[worker];
          CompactReader decoder({}, symbols, header);
          decoder.types = deferred->types;
          decoder.regions = deferred->regions;
          decoder.universes = deferred->universes;
          auto references = deferred->references;
          references.interface = [&](std::uint32_t declaration)
              -> std::optional<std::string_view> {
            const auto &names = decoder.pendingSymbols[static_cast<std::size_t>(
                SymbolKind::Interface)];
            if (declaration >= names.size())
              return {};
            return names[declaration];
          };
          std::vector<Type> canonicalReferences;
          const auto begin = count * worker / workers;
          const auto end = count * (worker + 1) / workers;
          result.edges.offsets.reserve(end - begin + 1);
          for (auto i = begin; i < end; ++i) {
            try {
              auto &slice = deferred->records[i];
              decoder.bytes =
                  bytes.subspan(slice.projectionOffset, slice.projectionLength);
              decoder.offset = 0;
              auto definition = compactDefinitionFor(deferred->kinds[i]);
              std::visit([&](auto &value) { decoder(value); }, definition);
              if (decoder.remaining())
                reject("trailing bytes in an indexed type record");
              slice.nominal = nominal(definition);
              if (slice.nominal != bool(hasIdentity[i]))
                reject("missing or unexpected logical definition identity");
              auto view = std::visit(
                  [](auto &record) -> CompactDefinitionView { return &record; },
                  definition);
              auto index = compactIndex(view, *decoder.arena);
              auto product = definitionRecord<ImportedProduct>(view);
              auto &scalars = deferred->scalars[i];
              scalars.parameterKind = index.parameterKind;
              scalars.valueType = index.valueType;
              scalars.declaration = index.declaration;
              scalars.payload = index.payload;
              scalars.region = index.region;
              scalars.genericOrigin = index.genericOrigin;
              scalars.regionOrigin = index.regionOrigin;
              if (product)
                scalars.aggregateKind = product->descriptor.kind;
              auto groups =
                  std::span(admission.groups)
                      .subspan(admission.offsets[i],
                               admission.offsets[i + 1] - admission.offsets[i]);
              lookupQueries(
                  deferred->kinds[i], index,
                  product ? product->descriptor.name : std::string_view{},
                  [&](const ImportedTypeQuery &query) {
                    if (!std::any_of(
                            groups.begin(), groups.end(),
                            [&](std::uint32_t group) {
                              auto key = deferred->lookup.group(group).key;
                              if (key.front() !=
                                  static_cast<std::uint8_t>(query.kind))
                                return false;
                              LookupKeyMatch match{key};
                              return writeLookupKey(match, query, references) &&
                                     match.exact();
                            }))
                      reject("type lookup index does not match projection");
                    ++result.memberships;
                  });
              if (!slice.nominal) {
                auto callable = definitionRecord<CallableType>(view);
                const bool symbolic =
                    deferred->kinds[i] == ImportedTypeKind::Erased ||
                    (callable && callable->function >= 0);
                regional[i] = index.regionOrigin != Type::Unknown;
                canonicalReferences.clear();
                auto &fingerprint = admittedFingerprints[i];
                fingerprint = 14695981039346656037ull;
                SymbolicKey symbolicKey{static_cast<std::uint32_t>(i), {}, {}};
                Writer key;
                key.discardBytes = !symbolic;
                key.typeReferences = &canonicalReferences;
                key.fingerprint = symbolic ? nullptr : &fingerprint;
                key.symbolFixups = symbolic ? &symbolicKey.symbols : nullptr;
                writeCanonicalKey(key, view);
                if (symbolic) {
                  symbolicKey.bytes = std::move(key.bytes);
                  result.symbolic.push_back(std::move(symbolicKey));
                }
                for (auto reference : canonicalReferences)
                  if (reference.index() >= builtinTypeCount)
                    result.edges.targets.push_back(graphIndex(ids, reference));
              }
              result.edges.offsets.push_back(result.edges.targets.size());
              decoder.arena->reset();
            } catch (const InvalidGraph &error) {
              failures[i] = error.message;
              break;
            }
          }
          result.symbols = std::move(decoder.pendingSymbols);
        } catch (...) {
          projections[worker].exception = std::current_exception();
        }
      };
      std::vector<std::jthread> threads;
      for (std::size_t worker = 1; worker < workers; ++worker)
        threads.emplace_back(validate, worker);
      validate(0);
      for (auto &thread : threads)
        thread.join();
      for (const auto &projection : projections)
        if (projection.exception)
          std::rethrow_exception(projection.exception);
      for (const auto &failure : failures)
        if (!failure.empty())
          reject(failure);
      for (auto &projection : projections) {
        std::array<std::size_t, Reader::symbolKinds> symbolBases;
        for (std::size_t kind = 0; kind < Reader::symbolKinds; ++kind) {
          symbolBases[kind] = reader.pendingSymbols[kind].size();
          reader.pendingSymbols[kind].insert(reader.pendingSymbols[kind].end(),
                                             projection.symbols[kind].begin(),
                                             projection.symbols[kind].end());
        }
        const auto offset = edges.targets.size();
        for (std::size_t i = 1; i < projection.edges.offsets.size(); ++i)
          edges.offsets.push_back(offset + projection.edges.offsets[i]);
        edges.targets.insert(edges.targets.end(),
                             projection.edges.targets.begin(),
                             projection.edges.targets.end());
        for (auto &key : projection.symbolic) {
          if (deferred->kinds[key.ordinal] == ImportedTypeKind::Erased)
            deferred->scalars[key.ordinal].declaration +=
                symbolBases[static_cast<std::size_t>(SymbolKind::Interface)];
          for (auto &symbol : key.symbols)
            symbol.index = static_cast<std::uint32_t>(
                symbolBases[static_cast<std::size_t>(symbol.kind)] +
                symbol.index);
          symbolicKeys.push_back(std::move(key));
        }
        memberships += projection.memberships;
      }
    }
    if (demand && !onUse && memberships != deferred->lookup.membershipCount)
      reject("incomplete or extraneous type lookup index");
    deferred->symbols = reader.resolveSymbols();
    if (onUse) {
      deferred->retainedSymbols = std::move(retainedSymbols);
      deferred->scalars.resize(ids.size());
    } else if (demand) {
      deferred->retainedSymbols = std::move(retainedSymbols);
      for (std::size_t kind = 0; kind < Reader::symbolKinds; ++kind)
        for (std::size_t i = 0; i < reader.pendingSymbols[kind].size(); ++i) {
          auto name = reader.pendingSymbols[kind][i];
          auto value = deferred->symbols[kind][i];
          if (deferred->symbolValues[kind].emplace(name, value).second &&
              kind == static_cast<std::size_t>(SymbolKind::Interface))
            deferred->interfaces[value].push_back(name);
        }
      auto callbacks = deferred->resolver();
      std::unordered_multimap<std::uint64_t, std::size_t> fingerprints;
      fingerprints.reserve(ids.size());
      auto projection = [&](std::size_t i, CompactReader &decoder) {
        const auto &slice = deferred->records[i];
        decoder.bytes =
            bytes.subspan(slice.projectionOffset, slice.projectionLength);
        decoder.offset = 0;
        decoder.types = deferred->types;
        decoder.regions = deferred->regions;
        decoder.universes = deferred->universes;
        auto definition = compactDefinitionFor(deferred->kinds[i]);
        std::visit([&](auto &value) { decoder(value); }, definition);
        auto view = std::visit(
            [](auto &record) -> CompactDefinitionView { return &record; },
            definition);
        std::array<CompactDefinitionView, 1> remapped{view};
        remapCompactSymbols(remapped, decoder.resolveSymbols());
        return definition;
      };
      for (auto &key : symbolicKeys) {
        if (deferred->kinds[key.ordinal] == ImportedTypeKind::Erased) {
          auto &declaration = deferred->scalars[key.ordinal].declaration;
          declaration =
              deferred->symbols[static_cast<std::size_t>(SymbolKind::Interface)]
                  .at(declaration);
        }
        for (const auto &symbol : key.symbols) {
          const std::uint64_t value =
              deferred->symbols[static_cast<std::size_t>(symbol.kind)].at(
                  symbol.index);
          for (unsigned byte = 0; byte < symbol.width; ++byte)
            key.bytes[symbol.offset + byte] =
                static_cast<std::uint8_t>(value >> (byte * 8));
        }
        auto &fingerprint = admittedFingerprints[key.ordinal];
        for (auto byte : key.bytes)
          fingerprint = (fingerprint ^ byte) * 1099511628211ull;
      }
      auto fullKey = [&](std::size_t i) {
        CompactReader decoder({}, callbacks, header);
        return canonicalKey(projection(i, decoder));
      };
      for (std::size_t i = 0; i < ids.size(); ++i) {
        if (deferred->records[i].nominal)
          continue;
        auto fingerprint = admittedFingerprints[i];
        auto [first, last] = fingerprints.equal_range(fingerprint);
        if (first != last) {
          auto key = fullKey(i);
          for (auto found = first; found != last; ++found)
            if (fullKey(found->second) == key) {
              uniqueKeys = false;
              break;
            }
        }
        if (!uniqueKeys)
          break;
        fingerprints.emplace(fingerprint, i);
      }
      if (uniqueKeys)
        recursiveRegionals(std::move(edges),
                           [&](std::size_t node) { return regional[node]; });
    } else {
      remapCompactSymbols(definitions, deferred->symbols);
      validateGraph(CompactTypes{candidate.regions(),
                                 candidate.targetPointerBits(),
                                 candidate.vaListAbi(), definitions},
                    ids, definitions);
      recursiveRegionals(ids, definitions, &uniqueKeys);
      for (const auto &definition : definitions)
        deferred->index.push_back(compactIndex(definition, *reader.arena));
      deferred->arena = std::move(reader.arena);
    }
    if (!uniqueKeys) {
      if (demand) {
        auto resolved = deferred->resolver();
        return importTypeGraphEager(types, bytes, resolved);
      }
      TypeGraphSymbols resolved = symbols;
      std::array<std::unordered_map<std::string_view, std::uint32_t>,
                 Reader::symbolKinds>
          values;
      for (std::size_t kind = 0; kind < Reader::symbolKinds; ++kind)
        for (std::size_t i = 0; i < reader.pendingSymbols[kind].size(); ++i)
          values[kind].emplace(reader.pendingSymbols[kind][i],
                               deferred->symbols[kind][i]);
      resolved.resolve =
          [&](SymbolKind kind,
              std::string_view name) -> std::optional<std::uint32_t> {
        return values[static_cast<std::size_t>(kind)].at(name);
      };
      return importTypeGraphEager(types, bytes, resolved);
    }
    deferred->definitions = std::move(definitions);
    if (demand) {
      deferred->symbols = {};
      deferred->validationRegions = candidate.regions();
      deferred->validationAbi = candidate.vaListAbi();
      deferred->demandedArena = std::make_shared<CompactArena>();
    }
    auto loader = std::make_shared<const TypeStore::ImportedDefinitionLoader>(
        [deferred](std::size_t i) { return deferred->materialize(i); });
    auto borrowed = std::make_shared<const TypeStore::BorrowedDefinitionLoader>(
        [deferred](std::size_t i) {
          deferred->validate(i);
          std::lock_guard lock(deferred->validationMutex);
          const auto &definition = deferred->retainedSymbols
                                       ? deferred->demandedDefinitions.at(i)
                                       : deferred->definitions.at(i);
          return std::visit(
              [](const auto *record) -> BorrowedTypeDefinition {
                return record;
              },
              definition);
        });
    TypeStore::ImportedTypeLookup resolve;
    TypeStore::ImportedTypeScalarLookup scalars;
    if (demand) {
      resolve = [deferred](const ImportedTypeQuery &query) {
        return deferred->resolve(query);
      };
      scalars = [deferred](std::size_t i) {
        return deferred->queryValidation ? deferred->project(i)
                                         : deferred->scalars.at(i);
      };
    }
    candidate.deferImportedDefinitions(ids, deferred->index, std::move(loader),
                                       std::move(borrowed), deferred,
                                       std::move(resolve), std::move(scalars));
    types = std::move(candidate);
    return result;
  } catch (const InvalidGraph &error) {
    return {{}, {}, error.message};
  }
}
} // namespace

TypeGraphImport
importTypeGraph(TypeStore &types, std::span<const std::uint8_t> bytes,
                const TypeGraphSymbols &symbols, ValidationMode validation,
                std::shared_ptr<const TypeGraphSymbols> retainedSymbols,
                std::shared_ptr<const void> backing) {
  if (validation != ValidationMode::Eager &&
      (!retainedSymbols || retainedSymbols.get() != &symbols ||
       types.storedTypeCount() || symbols.lookupDefinition))
    return {{},
            {},
            "demand-loaded types require a fresh graph and an owned resolver"};
  if (!types.storedTypeCount() && !symbols.lookupDefinition)
    return importCompactTypeGraph(types, bytes, symbols, validation,
                                  std::move(retainedSymbols),
                                  std::move(backing));
  return importTypeGraphEager(types, bytes, symbols);
}
} // namespace mettle::metadata
