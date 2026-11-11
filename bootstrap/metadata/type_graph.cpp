#include "metadata/type_graph.h"
#include "support/limits.h"
#include <algorithm>
#include <bit>
#include <limits>
#include <map>
#include <set>
#include <stdexcept>
#include <type_traits>

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
template <class A> void record(A &a, CallableParameter &r) {
  a(r.type, r.mode, r.name);
}
template <class A> void record(A &a, RegionRequirement &r) {
  a(r.longer, r.shorter);
}
template <class A> void record(A &a, CallableType &r) {
  a(r.parameters, r.result, r.error, r.abiResult, r.resultSources, r.mode,
    r.regions, r.environment);
  a.closure(r.function);
  a(r.name, r.regionParameters, r.parameterRegions);
  a.universe(r.regionUniverse);
  a(r.regionRequirements, r.resultFromEnvironment, r.environmentMode,
    r.unsafeCall, r.abi, r.variadic, r.targetFeatures);
}
template <class A> void record(A &a, TypeField &r) { a(r.name, r.type); }
template <class A> void record(A &a, VariantType &r) { a(r.name, r.fields); }
template <class A> void record(A &a, ProductLayout &r) {
  a(r.kind, r.alignment, r.packing, r.unionType, r.tag, r.pinnedFields,
    r.discriminants, r.unpin, r.unpinConditions, r.conditionalUnpin);
}
template <class A> void record(A &a, ProductType::VectorShape &r) {
  a(r.element, r.lanes, r.alignment);
}
template <class A> void record(A &a, ProductType &r) {
  a(r.name, r.fields, r.copyRequested, r.hasDestructor);
  a.function(r.destructor);
  a(r.kind, r.variants, r.components, r.genericParameters, r.genericOrigin,
    r.genericArguments, r.arrayCount, r.opaqueBounds);
  a.package(r.package);
  a(r.regionOrigin, r.regionArguments, r.regionPattern, r.layout,
    r.nativeCleanup, r.vector, r.normalizedFields);
}
template <class A> void record(A &a, TypeParameter &r) {
  a(r.name, r.copyRequested, r.sized, r.kind, r.valueType, r.value, r.operation,
    r.operands, r.callableConstraint, r.callableLocalParameters,
    r.regionArguments, r.unpin, r.numeric, r.erasedCallableConstraint);
}
template <class A> void record(A &a, TypeBinding &r) {
  a(r.parameter, r.argument);
}
template <class A> void record(A &a, ErasedType &r) {
  a(r.name);
  a.interface(r.declaration);
  a(r.arguments, r.associated, r.methods, r.methodTypes, r.methodOwners,
    r.methodSlots, r.parentInterfaces, r.regionArguments, r.regionParameters);
  a.universe(r.regionUniverse);
  a(r.regionRequirements, r.bound);
}
template <class A> void record(A &a, ViewType &r) {
  a(r.payload, r.mode, r.name, r.region);
}
template <class A> void record(A &a, SliceType &r) {
  a(r.element, r.name, r.metadata);
}
template <class A> void record(A &a, ImportedProduct &r) {
  a(r.descriptor, r.closure, r.coroutineInterior);
}
template <class A> void record(A &a, ImportedPointer &r) { a(r.descriptor); }
template <class A> void record(A &a, DefinitionIdentity &r) {
  a(r.package, r.definition, r.parameterOrdinal);
}

template <class Derived> struct Fields {
  template <class... T> void operator()(T &...values) {
    (static_cast<Derived *>(this)->value(values), ...);
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
  Graph &graph;
  const TypeGraphSymbols &symbols;
  std::vector<std::uint8_t> bytes;
  bool localReferences = false;
  std::vector<Type> *typeReferences = nullptr;
  const std::function<Type(Type)> *typeMapper = nullptr;
  Writer(Graph &graph, const TypeGraphSymbols &symbols)
      : graph(graph), symbols(symbols) {}
  void byte(std::uint8_t b) {
    if (bytes.size() >= limits::sourceBytes)
      reject("type graph exceeds source byte limit");
    bytes.push_back(b);
  }
  void u32(std::uint32_t n) {
    for (unsigned i = 0; i != 4; ++i)
      byte(static_cast<std::uint8_t>(n >> (8 * i)));
  }
  void u64(std::uint64_t n) {
    for (unsigned i = 0; i != 8; ++i)
      byte(static_cast<std::uint8_t>(n >> (8 * i)));
  }
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
  void value(Type &type) {
    if (typeMapper)
      type = (*typeMapper)(type);
    if (typeReferences) {
      typeReferences->push_back(type);
      u32(0);
    } else
      u32(localReferences ? type.index() : graph.type(type));
  }
  void value(RegionId &region) {
    u32(localReferences ? region.index() : graph.region(region));
  }
  void universe(RegionUniverse &universe) {
    u32(localReferences ? universe : graph.universe(universe));
  }
  void value(std::string &text) {
    if (text.size() > limits::sourceBytes)
      reject("type graph string exceeds source byte limit");
    u32(static_cast<std::uint32_t>(text.size()));
    for (unsigned char c : text)
      byte(c);
  }
  template <class T> void value(std::vector<T> &items) {
    if (items.size() > limits::sourceBytes)
      reject("type graph sequence exceeds source byte limit");
    u32(static_cast<std::uint32_t>(items.size()));
    for (auto &item : items)
      value(item);
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
    if (localReferences) {
      u32(index);
      return;
    }
    if (!symbols.symbol)
      reject("missing logical symbol mapper");
    auto logical = symbols.symbol(kind, index);
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
};
struct Reader : Fields<Reader> {
  std::span<const std::uint8_t> bytes;
  std::size_t offset = 0;
  const TypeGraphSymbols &symbols;
  const Header &header;
  bool scanning = true;
  std::span<const Type> types;
  std::span<const RegionId> regions;
  std::span<const RegionUniverse> universes;
  Reader(std::span<const std::uint8_t> bytes, const TypeGraphSymbols &symbols,
         const Header &header)
      : bytes(bytes), symbols(symbols), header(header) {}
  std::size_t remaining() const { return bytes.size() - offset; }
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
    if (!scanning)
      type = types[ref];
  }
  void value(RegionId &region) {
    auto ref = u32();
    if (ref >= 2 && ref - 2 >= header.regions)
      reject("dangling type graph region reference");
    if (!scanning)
      region = regions[ref];
  }
  void universe(RegionUniverse &universe) {
    auto ref = u32();
    if (ref >= header.universes)
      reject("dangling type graph universe reference");
    if (!scanning)
      universe = universes[ref];
  }
  void value(std::string &text) {
    auto count = u32();
    if (count > remaining())
      reject("truncated type graph string");
    if (!scanning)
      text.assign(reinterpret_cast<const char *>(bytes.data() + offset), count);
    offset += count;
  }
  template <class T> void value(std::vector<T> &items) {
    auto count = u32();
    if (count > remaining())
      reject("invalid type graph sequence length");
    if (scanning) {
      for (std::uint32_t i = 0; i < count; ++i) {
        T item{};
        value(item);
      }
    } else {
      items.resize(count);
      for (auto &item : items)
        value(item);
    }
  }
  template <class T> void value(std::optional<T> &item) {
    if (flag()) {
      T temporary{};
      value(temporary);
      if (!scanning)
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
      if (!scanning && !items.insert(std::move(text)).second)
        reject("duplicate type graph target feature");
    }
  }
  std::uint32_t symbol(SymbolKind kind) {
    std::string logical;
    value(logical);
    if (scanning)
      return 0;
    if (logical.empty() || !symbols.resolve)
      reject("missing logical symbol resolver");
    auto index = symbols.resolve(kind, logical);
    if (!index)
      reject("unresolved imported symbol: " + logical);
    return *index;
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
      if (!scanning && index == unknownPackage)
        reject("resolved package has invalid identity");
    }
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
bool nominal(const ImportedTypeDefinition &definition) {
  if (auto product = std::get_if<ImportedProduct>(&definition)) {
    const auto &r = product->descriptor;
    return r.genericOrigin == Type::Unknown &&
           r.regionOrigin == Type::Unknown &&
           (r.kind == AggregateKind::Product ||
            r.kind == AggregateKind::Enumeration ||
            r.kind == AggregateKind::Opaque ||
            r.kind == AggregateKind::NativeVector);
  }
  if (auto parameter = std::get_if<TypeParameter>(&definition))
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
    if (!a.scanning)
      r.sources.reserve(count);
    for (std::uint32_t i = 0; i < count; ++i) {
      auto ref = a.u32();
      if (ref >= 2 && ref - 2 >= a.header.regions)
        reject("dangling intersection source");
      if (!a.scanning)
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
constexpr std::uint32_t version = 2;
void readHeader(Reader &reader, Header &header, unsigned pointerBits) {
  if (reader.bytes.size() > limits::sourceBytes)
    reject("type graph exceeds source byte limit");
  for (auto expected : magic)
    if (reader.byte() != expected)
      reject("invalid type graph magic");
  if (reader.u32() != version)
    reject("incompatible type graph version");
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
    if (!reader.scanning)
      tables.kinds.push_back(kind);
  }
  for (std::uint32_t i = 0; i < reader.header.universes; ++i) {
    auto parent = reader.u32();
    if (i ? parent >= i : parent != 0)
      reject("cyclic or dangling region universe ancestry");
    if (!reader.scanning)
      tables.parents.push_back(parent);
  }
  for (std::uint32_t i = 0; i < reader.header.binders; ++i) {
    auto universe = reader.u32();
    if (universe >= reader.header.universes)
      reject("dangling region binder universe");
    if (!reader.scanning)
      tables.binders.push_back(universe);
  }
  for (std::uint32_t i = 0; i < reader.header.regions; ++i) {
    WireRegion region;
    record(reader, region);
    if (!reader.scanning)
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
  template <class T> void value(std::optional<T> &item) {
    if (item)
      static_cast<Derived *>(this)->value(*item);
  }
  template <class T, class U> void value(std::pair<T, U> &item) {
    (*static_cast<Derived *>(this))(item.first, item.second);
  }
};
std::vector<std::size_t>
acyclic(const std::vector<std::vector<std::size_t>> &edges) {
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
        if (depths[frame.node] > limits::typeDepth)
          reject("imported type nesting exceeds compiler depth limit");
        state[frame.node] = 2;
        order.push_back(frame.node);
        stack.pop_back();
      } else {
        auto next = edges[frame.node][frame.next++];
        if (state[next] == 1)
          reject("cyclic type graph");
        if (!state[next]) {
          if (stack.size() >= limits::typeDepth)
            reject("imported type nesting exceeds compiler depth limit");
          state[next] = 1;
          stack.push_back({next});
        }
      }
    }
  }
  return order;
}
void validateCallable(const TypeStore &store, const CallableType &r,
                      bool pointer) {
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
void validateGraph(const TypeStore &store, std::span<const Type> ids,
                   std::vector<ImportedTypeDefinition> &definitions) {
  std::map<Type, std::size_t> indices;
  for (std::size_t i = 0; i < ids.size(); ++i)
    indices.emplace(ids[i], i);
  std::vector<std::vector<std::size_t>> valueEdges(ids.size()),
      originEdges(ids.size()), interfaceEdges(ids.size());
  auto validType = [&](Type type) {
    return type != Type::Unknown && !store.isConstant(type);
  };
  for (std::size_t i = 0; i < definitions.size(); ++i) {
    auto &definition = definitions[i];
    if (auto imported = std::get_if<ImportedProduct>(&definition)) {
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
          originEdges[i].push_back(indices.at(origin));
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
      }
      for (const auto &field : r.fields) {
        if (!validType(field.type))
          reject("invalid product field type");
        if (store.isProduct(field.type) || store.isSlice(field.type))
          valueEdges[i].push_back(indices.at(field.type));
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
        valueEdges[i].clear();
        if (store.isProduct(r.components[0]) || store.isSlice(r.components[0]))
          valueEdges[i].push_back(indices.at(r.components[0]));
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
        case AggregateKind::VarArgs:
          fields(std::array{Type::U64, Type::U64, Type::U64});
          break;
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
        if (r.kind == AggregateKind::Ref || r.kind == AggregateKind::RefMut) {
          auto view = r.components[0];
          if (!store.isView(view) ||
              !store.isProduct(store.view(view).payload) ||
              store.product(store.view(view).payload).kind !=
                  AggregateKind::RefCell ||
              store.product(store.view(view).payload).components.size() != 1)
            reject("invalid dynamic borrow guard payload");
        }
      }
    } else if (auto parameter = std::get_if<TypeParameter>(&definition)) {
      const auto &r = *parameter;
      auto scalar = isInteger(r.valueType) || r.valueType == Type::Bool ||
                    r.valueType == Type::Char;
      if ((r.kind == TypeParameterKind::Type &&
           (r.valueType != Type::Unknown || !r.operands.empty())) ||
          (r.kind == TypeParameterKind::Constant &&
           (!scalar || !r.operands.empty())) ||
          (r.kind == TypeParameterKind::Value &&
           (!scalar || !r.operands.empty() ||
            (r.numeric.negative &&
             r.numeric.magnitude == std::array<std::uint64_t, 2>{}) ||
            !integerLiteralFits(r.numeric, r.valueType,
                                store.targetPointerBits()))))
        reject("invalid typed parameter or scalar constant");
      if (r.kind == TypeParameterKind::Expression) {
        static const std::set<std::string> operations{
            "+",  "-",  "*",  "/", "%",  "&", "|",  "^",  "<<",
            ">>", "==", "!=", "<", "<=", ">", ">=", "&&", "||"};
        if (!scalar || r.operands.size() != 2 ||
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
      if (r.kind == TypeParameterKind::Projection &&
          (r.operands.size() < 2 || !validType(r.operands[0]) ||
           !store.isErased(r.operands[1]) || r.value < 0 ||
           (r.valueType != Type::Unknown && !scalar)))
        reject("invalid interface projection");
      for (auto constraint : {r.callableConstraint, r.erasedCallableConstraint})
        if (constraint != Type::Unknown && !store.isFunctionPointer(constraint))
          reject("invalid callable parameter constraint");
      if (r.callableConstraint != Type::Unknown)
        for (auto local : r.callableLocalParameters)
          if (local >= store.callable(r.callableConstraint).parameters.size())
            reject("dangling callable constraint parameter");
    } else if (auto callable = std::get_if<CallableType>(&definition))
      validateCallable(store, *callable, true);
    else if (auto erased = std::get_if<ErasedType>(&definition)) {
      for (const auto &method : erased->methods)
        validateCallable(store, method, false);
      if ((!erased->methodTypes.empty() &&
           erased->methodTypes.size() != erased->methods.size()) ||
          erased->methodOwners.size() != erased->methodSlots.size())
        reject("erased interface dispatch arity mismatch");
      std::set<Type> associated;
      for (const auto &binding : erased->associated)
        if (!store.isParameter(binding.parameter) ||
            !validType(binding.argument) ||
            !associated.insert(binding.parameter).second)
          reject("invalid erased associated binding");
      for (auto method : erased->methodTypes)
        if (method != Type::Unknown && !store.isFunctionPointer(method))
          reject("invalid erased method type");
      for (auto owner : erased->methodOwners)
        if (!store.isErased(owner))
          reject("invalid erased method owner");
      for (auto parent : erased->parentInterfaces) {
        if (!store.isErased(parent))
          reject("invalid erased parent interface");
        interfaceEdges[i].push_back(indices.at(parent));
      }
    } else if (auto view = std::get_if<ViewType>(&definition)) {
      if (!validType(view->payload) || (view->mode != ParameterMode::Read &&
                                        view->mode != ParameterMode::Mut))
        reject("invalid view type");
    } else if (auto pointer = std::get_if<ImportedPointer>(&definition)) {
      if (!validType(pointer->descriptor.payload) ||
          pointer->descriptor.region != RegionId::Unspecified ||
          (pointer->descriptor.mode != ParameterMode::Read &&
           pointer->descriptor.mode != ParameterMode::Mut))
        reject("invalid pointer type");
    } else if (auto slice = std::get_if<SliceType>(&definition)) {
      if (!validType(slice->element) ||
          slice->metadata != PointerMetadata::ElementCount)
        reject("invalid slice element");
      if (store.isProduct(slice->element) || store.isSlice(slice->element))
        valueEdges[i].push_back(indices.at(slice->element));
    }
  }
  acyclic(originEdges);
  acyclic(interfaceEdges);
  auto order = acyclic(valueEdges);
  std::vector<bool> drops(ids.size());
  std::vector<std::uint64_t> expanded(ids.size(), 1), elements(ids.size(), 1);
  auto drop = [&](Type type) {
    if (store.isErased(type))
      return true;
    if (store.isParameter(type))
      return !store.parameter(type).copyRequested;
    return type.index() >= builtinTypeCount && drops[indices.at(type)];
  };
  for (auto i : order) {
    auto type = ids[i];
    if (store.isSlice(type))
      drops[i] = drop(store.slice(type).element);
    else if (store.isErased(type) || store.isParameter(type))
      drops[i] = drop(type);
    else if (store.isProduct(type)) {
      const auto &r = store.product(type);
      bool suppress = r.kind == AggregateKind::Uninit ||
                      r.kind == AggregateKind::ManualDrop ||
                      r.kind == AggregateKind::Atomic;
      drops[i] = !suppress &&
                 (r.hasDestructor || r.nativeCleanup != NativeCleanup::None ||
                  r.kind == AggregateKind::VarArgs ||
                  r.kind == AggregateKind::Coroutine);
      if (!suppress)
        for (const auto &field : r.fields)
          drops[i] = drops[i] || drop(field.type);
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
                       ? indices.at(element)
                       : ids.size();
      auto expandedInner = inner == ids.size() ? 1 : expanded[inner];
      auto elementsInner = inner == ids.size() ? 1 : elements[inner];
      auto product = [](std::uint64_t count, std::uint64_t inner,
                        std::uint64_t limit) {
        return count > limit / inner ? limit + 1 : count * inner;
      };
      expanded[i] = product(std::max<std::uint64_t>(1, length.value_or(1)),
                            expandedInner, TypeStore::expandedArrayTotal);
      elements[i] = product(std::max<std::uint64_t>(1, length.value_or(1)),
                            elementsInner, TypeStore::droppableArrayElements);
      if (r.arrayCount != Type::Unknown)
        drops[i] = drops[i] || drop(element);
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
}
struct Remap : SemanticWalk<Remap> {
  using SemanticWalk::value;
  std::function<Type(Type)> map;
  explicit Remap(std::function<Type(Type)> map) : map(std::move(map)) {}
  void value(Type &type) { type = map(type); }
};
bool equalDefinition(const TypeStore &store, ImportedTypeDefinition left,
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
  Graph graph(store);
  TypeGraphSymbols symbols;
  Writer a(graph, symbols), b(graph, symbols);
  a.localReferences = b.localReferences = true;
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
    if (!equalDefinition(consumer, a, b) ||
        left.types.size() != right.types.size() ||
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
std::string canonicalKey(const TypeStore &store,
                         ImportedTypeDefinition definition,
                         std::vector<Type> *references = nullptr,
                         const std::function<Type(Type)> *mapper = nullptr) {
  Graph graph(store);
  TypeGraphSymbols symbols;
  Writer key(graph, symbols);
  key.localReferences = true;
  key.typeReferences = references;
  key.typeMapper = mapper;
  key.byte(static_cast<std::uint8_t>(definition.index()));
  std::visit(
      [&](auto &r) {
        using T = std::decay_t<decltype(r)>;
        if constexpr (std::is_same_v<T, ImportedProduct>) {
          auto &p = r.descriptor;
          if (p.regionOrigin != Type::Unknown) {
            key.byte(0);
            key(p.regionOrigin, p.normalizedFields, p.regionArguments,
                p.fields);
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
        } else if constexpr (std::is_same_v<T, TypeParameter>) {
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
                r.regionArguments);
            break;
          default:
            reject("generic definition has no structural identity");
          }
        } else if constexpr (std::is_same_v<T, CallableType>) {
          r.name.clear();
          for (auto &parameter : r.parameters)
            parameter.name.clear();
          for (auto &region : r.regions)
            region.clear();
          key(r);
        } else if constexpr (std::is_same_v<T, ErasedType>) {
          key(r.declaration, r.arguments);
          if (mapper)
            for (auto &binding : r.associated) {
              binding.parameter = (*mapper)(binding.parameter);
              binding.argument = (*mapper)(binding.argument);
            }
          std::sort(r.associated.begin(), r.associated.end(),
                    [](const auto &a, const auto &b) {
                      return a.parameter < b.parameter;
                    });
          key.typeMapper = nullptr;
          key(r.associated);
          key.typeMapper = mapper;
          key(r.regionArguments, r.regionParameters, r.regionRequirements,
              r.bound, r.regionUniverse);
        } else if constexpr (std::is_same_v<T, ViewType>)
          key(r.payload, r.mode, r.region);
        else if constexpr (std::is_same_v<T, ImportedPointer>)
          key(r.descriptor.payload, r.descriptor.mode);
        else
          key(r.element);
      },
      definition);
  return {reinterpret_cast<const char *>(key.bytes.data()), key.bytes.size()};
}
std::vector<bool>
recursiveRegionals(const TypeStore &store, std::span<const Type> ids,
                   const std::vector<ImportedTypeDefinition> &definitions) {
  std::map<Type, std::size_t> indices;
  for (std::size_t i = 0; i < ids.size(); ++i)
    indices.emplace(ids[i], i);
  std::vector<std::vector<std::size_t>> edges(ids.size()), reverse(ids.size());
  for (std::size_t i = 0; i < ids.size(); ++i) {
    if (nominal(definitions[i]))
      continue;
    std::vector<Type> references;
    canonicalKey(store, definitions[i], &references);
    for (auto reference : references)
      if (reference.index() >= builtinTypeCount) {
        auto target = indices.at(reference);
        edges[i].push_back(target);
        reverse[target].push_back(i);
      }
  }
  struct Frame {
    std::size_t node, next = 0;
  };
  std::vector<Frame> stack;
  std::vector<bool> visited(ids.size()), recursive(ids.size());
  std::vector<std::size_t> order;
  for (std::size_t root = 0; root < ids.size(); ++root) {
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
      if (auto product = std::get_if<ImportedProduct>(&definitions[node]);
          product && product->descriptor.regionOrigin != Type::Unknown) {
        recursive[node] = true;
        edges[node].clear();
      }
  }
  acyclic(edges);
  return recursive;
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
    for (auto type : original.storedTypes()) {
      auto definition = original.importedDefinition(type);
      if (!nominal(definition))
        canonicalTypes.try_emplace(
            canonicalKey(original, std::move(definition)), type);
    }
    for (std::size_t i = 0; i < ids.size(); ++i)
      indices.emplace(ids[i], i);
    for (const auto &[source, target] : existing.types) {
      auto i = index(source);
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
    auto recursive = recursiveRegionals(decoded, ids, definitions);
    for (std::size_t i = 0; i < ids.size(); ++i)
      if (recursive[i] && state[i] != 2) {
        mapped[i] = candidate.declareImportedType(ImportedTypeKind::Product);
        state[i] = 2;
      }
  }
  Type build(Type source) {
    if (source.index() < builtinTypeCount)
      return source;
    auto i = index(source);
    if (state[i] == 2)
      return mapped[i];
    if (state[i] == 1)
      reject("cyclic structural type identity");
    if (++depth > limits::typeDepth)
      reject("imported type nesting exceeds compiler depth limit");
    state[i] = 1;
    std::function<Type(Type)> mapper = [&](Type type) { return build(type); };
    auto key = canonicalKey(candidate, definitions[i], nullptr, &mapper);
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
    for (std::size_t i = 0; i < ids.size(); ++i)
      install(i);
    for (std::size_t i = 0; i < ids.size(); ++i) {
      auto expected = definitions[i];
      remap(expected);
      if (!equalDefinition(candidate, expected,
                           candidate.importedDefinition(mapped[i])))
        reject("conflicting logical or structural type definition");
    }
  }

private:
  const TypeStore &original;
  TypeStore &candidate;
  std::span<const Type> ids;
  std::vector<ImportedTypeDefinition> &definitions;
  std::map<Type, std::size_t> indices;
  std::map<std::string, Type> canonicalTypes;
  std::vector<Type> mapped;
  std::vector<unsigned char> state, installed;
  unsigned depth = 0;
  std::size_t index(Type type) const { return indices.at(type); }
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

TypeGraphExport exportTypeGraph(const TypeStore &types,
                                std::span<const Type> roots,
                                const TypeGraphSymbols &symbols) {
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
    out.u32(version);
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
    for (auto byte : body.bytes)
      out.byte(byte);
    for (auto root : roots)
      out.u32(graph.type(root));
    return {std::move(out.bytes), {}};
  } catch (const InvalidGraph &error) {
    return {{}, error.message};
  }
}

TypeGraphImport importTypeGraph(TypeStore &types,
                                std::span<const std::uint8_t> bytes,
                                const TypeGraphSymbols &symbols) {
  try {
    Header header;
    Reader scan(bytes, symbols, header);
    readHeader(scan, header, types.targetPointerBits());
    auto tablesOffset = scan.offset;
    Tables ignored;
    readTables(scan, ignored);
    auto bodyOffset = scan.offset;
    for (std::uint32_t i = 0; i < header.types; ++i) {
      std::optional<DefinitionIdentity> identity;
      scan(identity);
      auto kind = static_cast<ImportedTypeKind>(bytes[tablesOffset + i]);
      auto definition = definitionFor(kind);
      std::visit([&](auto &r) { scan(r); }, definition);
    }
    for (std::uint32_t i = 0; i < header.roots; ++i) {
      Type root;
      scan(root);
    }
    if (scan.remaining())
      reject("trailing bytes in type graph");

    Reader reader(bytes, symbols, header);
    reader.scanning = false;
    reader.offset = tablesOffset;
    Tables tables;
    readTables(reader, tables);
    TypeStore candidate = types;
    std::vector<RegionId> regions;
    std::vector<RegionUniverse> universes;
    importRegions(candidate, tables, regions, universes);
    TypeStore decoded = candidate;
    auto localTypes = builtinTypes();
    for (auto kind : tables.kinds)
      localTypes.push_back(decoded.declareImportedType(kind));
    reader.types = localTypes;
    reader.regions = regions;
    reader.universes = universes;
    reader.offset = bodyOffset;
    std::vector<ImportedTypeDefinition> definitions;
    std::vector<std::optional<DefinitionIdentity>> logical;
    TypeGraphImport result;
    std::set<DefinitionIdentity> identities;
    for (std::uint32_t i = 0; i < header.types; ++i) {
      std::optional<DefinitionIdentity> identity;
      reader(identity);
      auto definition = definitionFor(tables.kinds[i]);
      std::visit([&](auto &r) { reader(r); }, definition);
      if (nominal(definition) != identity.has_value())
        reject("missing or unexpected logical definition identity");
      if (identity) {
        validIdentity(*identity,
                      std::holds_alternative<TypeParameter>(definition));
        if (!identities.insert(*identity).second)
          reject("duplicate logical definition identity");
      }
      logical.push_back(std::move(identity));
      definitions.push_back(std::move(definition));
    }
    for (std::size_t i = 0; i < definitions.size(); ++i)
      decoded.defineImportedType(localTypes[primitiveCount + i],
                                 definitions[i]);
    auto decodedIds = std::span(localTypes).subspan(primitiveCount);
    validateGraph(decoded, decodedIds, definitions);
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
    for (std::uint32_t i = 0; i < header.roots; ++i) {
      Type root;
      reader(root);
      result.roots.push_back(canonical.build(root));
    }
    types = std::move(candidate);
    return result;
  } catch (const InvalidGraph &error) {
    return {{}, {}, error.message};
  }
}
} // namespace mettle::metadata
