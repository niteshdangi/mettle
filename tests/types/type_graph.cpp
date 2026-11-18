#include "metadata/type_graph.h"
#include "types/machine.h"
#include "types/project.h"
#include <algorithm>
#include <atomic>
#include <cstdlib>
#include <iostream>
#include <map>
#include <string>
#include <thread>

using namespace mettle;
using namespace mettle::metadata;
namespace {
void expect(bool condition, std::string_view message) {
  if (!condition) {
    std::cerr << message << '\n';
    std::exit(1);
  }
}
std::string symbolName(SymbolKind kind, std::uint32_t index) {
  return std::to_string(static_cast<unsigned>(kind)) + ":" +
         std::to_string(index);
}
TypeGraphSymbols symbolMaps(unsigned offset = 0) {
  TypeGraphSymbols symbols;
  symbols.symbol = [offset](SymbolKind kind,
                            std::uint32_t index) -> std::optional<std::string> {
    if (index < offset)
      return {};
    return symbolName(kind, index - offset);
  };
  symbols.resolve =
      [offset](SymbolKind kind,
               std::string_view name) -> std::optional<std::uint32_t> {
    for (unsigned index : {3u, 7u, 11u, 17u})
      if (symbolName(kind, index) == name)
        return index + offset;
    return {};
  };
  return symbols;
}
std::uint32_t u32(const std::vector<std::uint8_t> &bytes, std::size_t offset) {
  std::uint32_t result = 0;
  for (unsigned i = 0; i < 4; ++i)
    result |= static_cast<std::uint32_t>(bytes[offset + i]) << (8 * i);
  return result;
}
void put32(std::vector<std::uint8_t> &bytes, std::size_t offset,
           std::uint32_t value) {
  for (unsigned i = 0; i < 4; ++i)
    bytes[offset + i] = static_cast<std::uint8_t>(value >> (8 * i));
}
} // namespace
int main() {
  {
    TypeStore types;
    auto leaf = types.declareProduct("Leaf", true);
    types.defineProduct(leaf, {{"value", Type::Bool}});
    auto root = leaf;
    for (unsigned i = 0; i < 48; ++i) {
      auto parent = types.declareProduct("Pair" + std::to_string(i), true);
      types.defineProduct(parent, {{"left", root}, {"right", root}});
      root = parent;
    }
    auto choice = types.declareProduct("Choice", true);
    types.defineEnumeration(choice, {{"First", {0}}, {"Second", {1}}},
                            {{"first", root}, {"second", root}});
    expect(!types.needsDrop(root) && !types.uninhabited(root) &&
               !types.uninhabited(choice),
           "shared type graphs retain inhabited, non-droppable leaves");
    auto snapshot = types;
    types.defineProduct(leaf, {{"value", Type::Never}});
    types.setDestructor(leaf, 0);
    expect(types.needsDrop(root) && types.uninhabited(root) &&
               types.uninhabited(choice) && !snapshot.needsDrop(root) &&
               !snapshot.uninhabited(root),
           "type property queries follow changed definitions, not snapshots");
    types.defineEnumeration(choice, {{"Empty", {}}, {"Value", {0}}},
                            {{"value", root}});
    expect(!types.uninhabited(choice),
           "an inhabited variant keeps an otherwise empty sum inhabited");
  }
  {
    TypeStore types;
    auto first = types.declareProduct("First", true);
    auto second = types.declareProduct("Second", true);
    types.defineProduct(first, {{"next", second}, {"empty", Type::Never}});
    types.defineProduct(second, {{"next", first}});
    auto either = types.declareProduct("Either", true);
    types.defineProduct(either, {{"first", first}, {"second", second}});
    ProductLayout layout;
    layout.unionType = true;
    types.setProductLayout(either, layout);
    expect(types.uninhabited(either) && !types.needsDrop(either),
           "cyclic properties do not reuse an incomplete negative proof");
    types.defineProduct(first, {{"next", second}});
    types.setDestructor(second, 0);
    expect(!types.uninhabited(either) && types.needsDrop(either),
           "cyclic queries terminate and discover reachable destructors");
  }
  {
    TypeStore producer;
    auto payload = producer.declareProduct("Payload", true);
    producer.defineProduct(payload, {{"value", Type::I32}});
    auto unused = producer.declareProduct("Unused", true);
    producer.defineProduct(unused, {{"invalid", Type::Unknown}});
    auto holder = producer.declareProduct("Holder", true);
    producer.defineProduct(holder, {{"payload", payload}});
    auto wrapper = producer.declareProduct("Wrapper", true);
    producer.defineProduct(wrapper, {{"holder", holder}});
    auto row =
        producer.arrayType(Type::I32, producer.constant(Type::Usize, 32));
    auto matrix = producer.arrayType(row, producer.constant(Type::Usize, 40));
    TypeGraphSymbols symbols;
    symbols.definition = [&producer](Type type) {
      return std::optional(DefinitionIdentity{
          "demand", std::string(producer.name(type)), std::nullopt});
    };
    auto encoded = exportTypeGraph(
        producer, std::array{holder, unused, wrapper, row, matrix}, symbols,
        ValidationMode::OnDemand);
    expect(bool(encoded), "indexed type graph did not export");
    TypeStore eager;
    expect(!importTypeGraph(eager, encoded.bytes, {}),
           "eager import accepted an invalid unused type");
    auto retained = std::make_shared<const TypeGraphSymbols>();
    TypeStore consumer;
    auto imported = importTypeGraph(consumer, encoded.bytes, *retained,
                                    ValidationMode::OnDemand, retained);
    expect(bool(imported), imported.error);
    encoded.bytes.clear();
    retained.reset();
    expect(consumer.isCopy(imported.roots[0]) &&
               consumer.product(imported.roots[0]).fields.size() == 1,
           "demanded type dependencies lost validation or retained bytes");
    expect(consumer.product(imported.roots[2]).fields[0].type ==
               imported.roots[0],
           "demand validation must reuse a proved dependency closure");
    expect(consumer.product(imported.roots[3]).fields.size() == 32 &&
               consumer.product(imported.roots[4]).arrayCount != Type::Unknown,
           "reused array proofs must preserve nested expansion counts");
    for (unsigned attempt = 0; attempt < 2; ++attempt) {
      bool rejected = false;
      try {
        (void)consumer.product(imported.roots[1]);
      } catch (const InvalidMetadata &) {
        rejected = true;
      }
      expect(rejected, "invalid demanded type was published before validation");
    }
    auto changed = consumer;
    changed.defineProduct(imported.roots[0], {{"changed", Type::Bool}});
    expect(consumer.product(imported.roots[0]).fields[0].name == "payload",
           "demand-loaded type mutation changed its retained snapshot");
  }
  {
    TypeStore producer;
    ErasedType descriptor;
    descriptor.name = "any Alias";
    descriptor.declaration = 3;
    auto first = producer.erasedType(descriptor);
    descriptor.declaration = 7;
    auto second = producer.erasedType(descriptor);
    auto maps = symbolMaps();
    maps.resolve = [](SymbolKind kind,
                      std::string_view name) -> std::optional<std::uint32_t> {
      if (kind == SymbolKind::Interface &&
          (name == symbolName(kind, 3) || name == symbolName(kind, 7)))
        return 17;
      return {};
    };
    auto retained = std::make_shared<const TypeGraphSymbols>(maps);
    auto encoded = exportTypeGraph(producer, std::array{first, second}, maps,
                                   ValidationMode::OnDemand);
    expect(bool(encoded), encoded.error);
    TypeStore consumer;
    auto imported = importTypeGraph(consumer, encoded.bytes, *retained,
                                    ValidationMode::OnDemand, retained);
    expect(bool(imported), imported.error);
    descriptor.declaration = 17;
    expect(imported.roots[0] == imported.roots[1] &&
               consumer.erasedType(descriptor) == imported.roots[0],
           "resolved symbol aliases share one canonical type identity");
  }
  {
    TypeStore producer;
    auto callable = producer.callableType(CallableType{});
    auto retained = std::make_shared<const TypeGraphSymbols>();
    auto encoded = exportTypeGraph(producer, std::array{callable}, *retained,
                                   ValidationMode::OnDemand);
    expect(bool(encoded), encoded.error);
    auto identityFrame =
        36 + u32(encoded.bytes, 16) + 4 * u32(encoded.bytes, 24) + 1;
    auto fullRecord = identityFrame + 4 + u32(encoded.bytes, identityFrame) + 4;
    put32(encoded.bytes, fullRecord + 12, Type::Bool.index());
    TypeStore consumer;
    auto imported = importTypeGraph(consumer, encoded.bytes, *retained,
                                    ValidationMode::OnDemand, retained);
    expect(bool(imported), imported.error);
    bool rejected = false;
    try {
      (void)consumer.callable(imported.roots[0]);
    } catch (const InvalidMetadata &error) {
      rejected = std::string_view(error.what())
                     .find("type record does not match its identity index") !=
                 std::string_view::npos;
    }
    expect(rejected,
           "demanded ABI results must match identity fields outside the index");
  }
  {
    TypeStore producer;
    auto four = producer.structural(AggregateKind::Array, {Type::I32}, 4);
    auto six = producer.structural(AggregateKind::Array, {Type::I32}, 6);
    auto wide = producer.structural(AggregateKind::Array, {Type::I64}, 7);
    auto pointer = producer.pointerType(four, ParameterMode::Read);
    auto retained = std::make_shared<const TypeGraphSymbols>();
    auto encoded =
        exportTypeGraph(producer, std::array{four, pointer, six, wide},
                        *retained, ValidationMode::OnDemand);
    expect(bool(encoded), encoded.error);
    TypeStore original;
    auto imported = importTypeGraph(original, encoded.bytes, *retained,
                                    ValidationMode::OnDemand, retained);
    expect(bool(imported), imported.error);
    four = imported.roots[0];
    pointer = imported.roots[1];
    original.shareInterning();
    auto changed = original;
    expect(changed.structural(AggregateKind::Array, {Type::I32}, 4) == four &&
               changed.structural(AggregateKind::Array, {Type::I32}, 6) ==
                   imported.roots[2] &&
               changed.structural(AggregateKind::Array, {Type::I64}, 7) ==
                   imported.roots[3] &&
               changed.pointerType(four, ParameterMode::Read) == pointer,
           "copied imports preserve all candidates and adjacent key groups");
    auto five = changed.structural(AggregateKind::Array, {Type::I32}, 5);
    expect(changed.structural(AggregateKind::Array, {Type::I32}, 5) == five &&
               changed.structural(AggregateKind::Array, {Type::I32}, 4) ==
                   four &&
               changed.storedTypeCount() == original.storedTypeCount() + 1,
           "local interning additions preserve the immutable imported index");
    auto definition = changed.importedDefinition(four);
    auto &array = std::get<ImportedProduct>(definition).descriptor;
    array.components = {Type::I64};
    for (auto &field : array.fields)
      field.type = Type::I64;
    changed.defineImportedType(four, std::move(definition));
    expect(
        changed.structural(AggregateKind::Array, {Type::I64}, 4) == four &&
            changed.structural(AggregateKind::Array, {Type::I32}, 4) != four &&
            original.structural(AggregateKind::Array, {Type::I32}, 4) == four &&
            original.product(four).fields.front().type == Type::I32 &&
            original.pointerType(four, ParameterMode::Read) == pointer,
        "mutating an imported key invalidates only its consumer index");
  }
  {
    TypeRecords<std::string> records;
    std::atomic<unsigned> loaded = 0;
    auto loader = std::make_shared<const TypeRecords<std::string>::Loader>(
        [&](std::size_t value) {
          ++loaded;
          return std::to_string(value);
        });
    for (std::size_t i = 0; i < 2; ++i) {
      records.push_uninitialized();
      records.defer(i, i + 7, loader);
    }
    auto consumer = records;
    expect(loaded == 0, "copying deferred records materialized them");
    std::vector<std::jthread> readers;
    for (unsigned i = 0; i < 8; ++i)
      readers.emplace_back([&, i] {
        const auto &table = i < 4 ? records : consumer;
        expect(table[i % 2] == std::to_string(i % 2 + 7),
               "concurrent deferred record materialization lost a value");
      });
    readers.clear();
    expect(loaded == 2, "shared deferred records were decoded repeatedly");
    auto retained = records.retain(0);
    consumer.edit(0) = "consumer";
    records.clear();
    expect(*retained == "7" && std::as_const(consumer)[0] == "consumer",
           "deferred record mutation changed a retained snapshot");
  }
  {
    std::size_t loaded = 0;
    TypeStore types;
    auto product = types.declareImportedType(ImportedTypeKind::Product);
    struct BorrowedProduct {
      std::array<BasicTypeField<BorrowedTypeStorage>, 1> fields{
          BasicTypeField<BorrowedTypeStorage>{"value", Type::I32}};
      BasicImportedProduct<BorrowedTypeStorage> record;
    };
    auto borrowed = std::make_shared<BorrowedProduct>();
    borrowed->record.descriptor.name = "Borrowed";
    borrowed->record.descriptor.copyRequested = true;
    borrowed->record.descriptor.fields = std::span(borrowed->fields);
    ImportedProduct owned;
    owned.descriptor.name = "Borrowed";
    owned.descriptor.copyRequested = true;
    owned.descriptor.fields = {{"value", Type::I32}};
    auto loader = std::make_shared<const TypeStore::ImportedDefinitionLoader>(
        [owned, &loaded](std::size_t) -> ImportedTypeDefinition {
          ++loaded;
          return owned;
        });
    auto views = std::make_shared<const TypeStore::BorrowedDefinitionLoader>(
        [borrowed](std::size_t) -> BorrowedTypeDefinition {
          return &borrowed->record;
        });
    types.deferImportedDefinitions(
        std::array{product}, std::array{ImportedTypeIndex{}}, loader, views);
    expect(types.isCopy(product) && types.isSized(product) &&
               !types.needsDrop(product) && !types.uninhabited(product) &&
               !containsVarArgs(types, product) && loaded == 0,
           "read-only type proofs must not expand owned imported records");
    auto changed = types;
    changed.defineProduct(product, {{"value", changed.sliceType(Type::I32)}});
    expect(!changed.isSized(product) && types.isSized(product) && loaded == 1,
           "borrowed proofs detach and follow the current definition");
    expect(changed.inspectProduct(
               product,
               [&](const auto &record) {
                 const auto original = record.fields.front().type;
                 changed.defineProduct(product, {{"value", Type::Bool}});
                 return record.fields.front().type == original;
               }) &&
               changed.isSized(product),
           "inspection pins the definition across consumer mutation");
  }
  {
    TypeStore prefix;
    auto node = prefix.declareProduct("Node", true);
    prefix.defineProduct(
        node, {{"next", prefix.pointerType(node, ParameterMode::Read)}});
    prefix.shareInterning();
    TypeStore source = prefix;
    source.declareProduct("Discarded", false);
    for (unsigned i = 0; i < 8; ++i)
      source.regions().binder(0, true);
    auto owner = source.regions().binder(0, true);
    auto a = source.regions().bound(owner, "a");
    auto b = source.regions().rigid(owner, "b");
    auto lifetime = source.regions().intersection({a, b});
    auto view = source.viewType(node, ParameterMode::Read, lifetime);
    TypeProjection projection(source, &prefix);
    auto projected = projection.type(view);
    const auto &store = *projection.store();
    expect(
        store.view(projected).payload == node &&
            &store.product(node) == &prefix.product(node) &&
            store.storedTypes().size() == prefix.storedTypes().size() + 1,
        "projection retains only live consumer types over the shared prefix");
    const auto &region = store.regions().get(store.view(projected).region);
    expect(
        region.kind == RegionKind::Intersection && region.sources.size() == 2 &&
            store.regions().get(region.sources[0]).binder ==
                store.regions().get(region.sources[1]).binder &&
            store.regions().get(region.sources[0]).universe ==
                store.regions().get(region.sources[1]).universe &&
            store.regions().universeCount() ==
                prefix.regions().universeCount() + 1,
        "projection preserves shared binders without retaining dead universes");
  }
  {
    TypeStore types;
    auto four = types.structural(AggregateKind::Array, {Type::I32}, 4);
    auto pointer = types.pointerType(four, ParameterMode::Read);
    types.shareInterning();
    TypeStore consumer = types;
    consumer.refreshProductInstances({});
    expect(consumer.structural(AggregateKind::Array, {Type::I32}, 4) == four &&
               &consumer.product(four) == &types.product(four),
           "read-only interning and refresh preserve shared type storage");
    auto five = consumer.structural(AggregateKind::Array, {Type::I32}, 5);
    expect(consumer.structural(AggregateKind::Array, {Type::I32}, 4) == four &&
               five != four &&
               consumer.structural(AggregateKind::Array, {Type::I32}, 5) ==
                   five &&
               consumer.pointerType(four, ParameterMode::Read) == pointer,
           "consumer interning searches both shared and private candidates");
    auto definition = consumer.importedDefinition(four);
    auto &array = std::get<ImportedProduct>(definition).descriptor;
    array.components = {Type::I64};
    for (auto &field : array.fields)
      field.type = Type::I64;
    consumer.defineImportedType(four, std::move(definition));
    expect(consumer.structural(AggregateKind::Array, {Type::I32}, 4) != four &&
               types.structural(AggregateKind::Array, {Type::I32}, 4) == four,
           "changed interning keys invalidate only the consumer index");
  }
  {
    TypeStore producer;
    auto parameter = producer.declareParameter("T", false);
    auto nominal = producer.declareProduct("Phantom", true);
    producer.setGenericParameters(nominal, {parameter});
    producer.defineProduct(nominal, {});
    auto plain = producer.viewType(Type::U8, ParameterMode::Read);
    auto instance = producer.instantiateProduct(nominal, {plain});
    auto scope = producer.regions().binder();
    auto a = producer.regions().bound(scope, "a");
    auto b = producer.regions().bound(scope, "b");
    auto first = producer.regionalShell(
        instance, {}, {producer.viewType(Type::U8, ParameterMode::Read, a)},
        Type::Unknown);
    auto second = producer.regionalShell(
        instance, {}, {producer.viewType(Type::U8, ParameterMode::Read, b)},
        Type::Unknown);
    auto equivalent = producer.regionalShell(
        instance, {}, {producer.viewType(Type::U8, ParameterMode::Read, a)},
        Type::Unknown);
    auto firstProduct = producer.regionalProduct(first, {}, {});
    auto secondProduct = producer.regionalProduct(second, {}, {});
    expect(firstProduct != secondProduct &&
               producer.regionalProduct(equivalent, {}, {}) == firstProduct,
           "regional products intern by generic arguments");
    TypeGraphSymbols symbols;
    symbols.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      if (type == nominal)
        return DefinitionIdentity{"package", "Phantom", {}};
      if (type == parameter)
        return DefinitionIdentity{"package", "Phantom", 0};
      return {};
    };
    std::array roots{first, second, equivalent};
    auto encoded = exportTypeGraph(producer, roots, symbols);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore consumer;
    auto decoded = importTypeGraph(consumer, encoded.bytes, symbols);
    expect(static_cast<bool>(decoded), decoded.error);
    expect(decoded.roots[0] != decoded.roots[1] &&
               decoded.roots[0] == decoded.roots[2],
           "regional generic arguments retain distinct canonical identities");
    const auto &left = consumer.product(decoded.roots[0]).genericArguments;
    const auto &right = consumer.product(decoded.roots[1]).genericArguments;
    expect(left.size() == 1 && right.size() == 1 &&
               consumer.view(left[0]).region != consumer.view(right[0]).region,
           "regional generic argument regions survive import");
  }
  {
    TypeStore types;
    auto payload = types.declareProduct("Conditional", true);
    auto parameter = types.declareParameter("T", false);
    types.setGenericParameters(payload, {parameter});
    types.defineProduct(payload, {{"value", parameter}});
    auto instance = types.instantiateProduct(payload, {parameter});
    auto tuple = types.structural(AggregateKind::Tuple, {instance, instance});
    auto optional = types.structural(AggregateKind::Optional, {instance});
    auto array = types.arrayType(instance,
                                 types.declareConstParameter("N", Type::Usize));
    types.setConditionalCopy(payload, {0});
    expect(!types.isCopy(tuple) && !types.isCopy(optional) &&
               !types.isCopy(array),
           "structural Copy follows finalized nominal payload constraints");
    auto later = types.structural(AggregateKind::Tuple, {instance});
    types.constrainParameter(parameter, true, true);
    expect(types.isCopy(tuple) && types.isCopy(optional) &&
               types.isCopy(array) && types.isCopy(later),
           "structural Copy follows strengthened payload bounds");
  }
  std::vector<std::uint8_t> bytes, indexedBytes;
  std::map<DefinitionIdentity, Type> importedNames;
  {
    TypeStore producer;
    auto symbols = symbolMaps();
    std::map<Type, DefinitionIdentity> identities;
    auto definition = [&](Type type, std::string name,
                          std::optional<std::uint32_t> ordinal = {}) {
      identities.emplace(
          type, DefinitionIdentity{"core@revision", std::move(name), ordinal});
      return type;
    };
    auto node =
        definition(producer.declareProduct("core::Node", false), "core::Node");
    auto t = definition(producer.declareParameter("T", true), "core::Node", 0);
    auto n = definition(producer.declareConstParameter("N", Type::Usize),
                        "core::Node", 1);
    auto f = definition(producer.declareParameter("F", false), "core::Node", 2);
    auto associated =
        definition(producer.declareParameter("Item", true), "core::Trait", 0);
    auto associatedCount = definition(
        producer.declareConstParameter("Count", Type::I32), "core::Trait", 1);
    auto associatedValue = definition(
        producer.declareConstParameter("Value", node), "core::Trait", 2);
    producer.setGenericParameters(node, {t, n, f});
    auto outer = producer.regions().binder();
    auto inner = producer.regions().binder(outer.universe, true);
    auto bound = producer.regions().bound(inner, "a");
    auto rigid = producer.regions().rigid(inner, "b");
    auto local = producer.regions().local(outer);
    auto inference = producer.regions().inference(inner);
    auto intersection = producer.regions().intersection({bound, rigid, local});
    auto readT = producer.viewType(t, ParameterMode::Read, bound);
    CallableType higher;
    higher.parameters = {{readT, ParameterMode::Read, "input"}};
    higher.result = producer.viewType(t, ParameterMode::Read, intersection);
    higher.abiResult = higher.result;
    higher.regionParameters = {bound};
    higher.parameterRegions = {bound};
    higher.regionUniverse = inner.universe;
    higher.regionRequirements = {{bound, local}, {rigid, inference}};
    higher.resultSources = {0};
    higher.abi = "C";
    higher.targetFeatures = {"sse2"};
    auto higherType = producer.callableType(higher);
    expect(producer.constrainCallableParameter(f, higherType, {0}),
           "producer callable constraint");
    ErasedType simple;
    simple.name = "any core::Simple";
    simple.declaration = 7;
    auto simpleErased = producer.erasedType(simple);
    auto associatedValueProjection =
        producer.projection(t, simpleErased, 2, {}, node);
    ErasedType trait;
    trait.name = "any core::Trait<T>";
    trait.declaration = 7;
    trait.arguments = {t};
    trait.associated = {{associated, t},
                        {associatedCount, producer.constant(Type::I32, 7)},
                        {associatedValue, associatedValueProjection}};
    trait.regionArguments = {local};
    trait.regionParameters = {bound};
    trait.regionUniverse = inner.universe;
    trait.regionRequirements = {{bound, local}};
    trait.bound = local;
    auto erased = producer.erasedType(trait);
    producer.setErasedMethods(erased, {higher});
    producer.setErasedDispatch(erased, {erased}, {3});
    auto projection = producer.projection(t, erased, 0, {t}, Type::Unknown,
                                          true, true, {bound});
    auto expression = producer.constantExpression(
        "+", {n, producer.constant(Type::Usize, 1)});
    auto symbolicArray = producer.arrayType(t, expression);
    producer.defineProduct(
        node, {{"next", producer.pointerType(node, ParameterMode::Mut)},
               {"items", symbolicArray},
               {"callback", f},
               {"associated", projection}});
    producer.setDestructor(node, 11);
    producer.setProductPackage(node, 3);
    ProductLayout layout;
    layout.alignment = 16;
    layout.pinnedFields = {0};
    layout.unpin = 1;
    layout.unpinConditions = {{0, 7}};
    producer.setProductLayout(node, layout);
    auto closureDescriptor = higher;
    closureDescriptor.function = 17;
    auto closure =
        definition(producer.closureType("core::capture", {{"borrow", readT}},
                                        closureDescriptor),
                   "core::capture");
    producer.setCoroutineInterior(closure, {symbolicArray, erased});
    auto coroutine =
        producer.structural(AggregateKind::Coroutine, {Type::I32, closure});
    auto opaque = definition(
        producer.opaqueType("core::Hidden", closure, {erased}), "core::Hidden");
    auto regional = producer.regionalProduct(
        node, {{"borrow", producer.viewType(t, ParameterMode::Read, local)}},
        {local}, true);
    auto enumeration = definition(producer.declareProduct("core::Choice", true),
                                  "core::Choice");
    producer.defineEnumeration(enumeration, {{"empty", {}}, {"value", {1}}},
                               {{"<tag>", Type::I32}, {"value", Type::I32}});
    ProductLayout enumLayout;
    enumLayout.kind = LayoutKind::Integer;
    enumLayout.discriminants = {integerLiteral(-2), integerLiteral(9)};
    producer.setProductLayout(enumeration, enumLayout);
    auto vector = definition(
        producer.vectorType("core::I32x4", Type::I32, 4, 16), "core::I32x4");
    auto concreteCount = producer.constant(Type::Usize, 65);
    auto compact = producer.arrayType(Type::I32, concreteCount);
    CallableType plain;
    plain.parameters = {{Type::I32, ParameterMode::Value, "x"}};
    plain.result = plain.abiResult = Type::I32;
    std::vector<Type> roots{
        node,
        t,
        n,
        f,
        compact,
        concreteCount,
        higherType,
        erased,
        projection,
        closure,
        coroutine,
        opaque,
        regional,
        expression,
        producer.viewType(Type::I32, ParameterMode::Read, RegionId::Static),
        producer.sliceType(Type::I32),
        producer.callableType(plain),
        simpleErased,
        enumeration,
        vector,
        compact};
    roots.push_back(producer.instantiateProduct(
        node, {Type::I32, concreteCount, producer.callableType(plain)}));
    auto other =
        definition(producer.declareParameter("T", true), "core::Other", 0);
    roots.push_back(other);
    for (auto kind :
         {AggregateKind::Optional, AggregateKind::Outcome, AggregateKind::Tuple,
          AggregateKind::Range, AggregateKind::Uninit,
          AggregateKind::ManualDrop, AggregateKind::UnsafeCell,
          AggregateKind::Cell, AggregateKind::RefCell, AggregateKind::Pin,
          AggregateKind::Atomic, AggregateKind::Ordering,
          AggregateKind::PhantomPinned, AggregateKind::VarArgs,
          AggregateKind::BorrowError, AggregateKind::BorrowMutError}) {
      std::vector<Type> components;
      if (kind == AggregateKind::Outcome || kind == AggregateKind::Tuple ||
          kind == AggregateKind::Range)
        components = {Type::I32, Type::Bool};
      else if (kind != AggregateKind::Ordering &&
               kind != AggregateKind::PhantomPinned &&
               kind != AggregateKind::VarArgs &&
               kind != AggregateKind::BorrowError &&
               kind != AggregateKind::BorrowMutError)
        components = {Type::I32};
      roots.push_back(producer.structural(kind, std::move(components)));
    }
    auto cell = producer.structural(AggregateKind::RefCell, {Type::I32});
    auto cellView = producer.viewType(cell, ParameterMode::Read, local);
    roots.push_back(producer.structural(AggregateKind::Ref, {cellView}));
    roots.push_back(producer.structural(AggregateKind::RefMut, {cellView}));
    symbols.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      auto found = identities.find(type);
      return found == identities.end() ? std::nullopt
                                       : std::optional(found->second);
    };
    auto encoded = exportTypeGraph(producer, roots, symbols);
    expect(static_cast<bool>(encoded), encoded.error);
    bytes = std::move(encoded.bytes);
    auto indexed =
        exportTypeGraph(producer, roots, symbols, ValidationMode::OnDemand);
    expect(bool(indexed), indexed.error);
    indexedBytes = std::move(indexed.bytes);
  }
  for (auto mode : {ValidationMode::Eager, ValidationMode::OnDemand}) {
    TypeStore fresh;
    auto temporary = mode == ValidationMode::Eager ? bytes : indexedBytes;
    auto symbols = std::make_shared<const TypeGraphSymbols>(symbolMaps(100));
    auto imported = importTypeGraph(fresh, temporary, *symbols, mode, symbols);
    expect(static_cast<bool>(imported), imported.error);
    temporary.clear();
    temporary.shrink_to_fit();
    const auto &roots = imported.roots;
    expect(fresh.isParameter(roots[1]) && fresh.isConstParameter(roots[2]) &&
               fresh.isProjection(roots[8]) &&
               fresh.erasedDeclaration(roots[7]) == 107 &&
               !containsVarArgs(fresh, roots[4]),
           "borrowed admission facts outlive the caller's wire buffer");
    auto changed = fresh;
    auto definition = changed.importedDefinition(roots[8]);
    std::get<TypeParameter>(definition).valueType = Type::I32;
    changed.defineImportedType(roots[8], std::move(definition));
    expect(changed.isConstant(roots[8]) && !changed.isParameter(roots[8]) &&
               fresh.isParameter(roots[8]),
           "borrowed classification follows detached definition changes");
    expect(fresh.arrayType(Type::I32, fresh.constant(Type::Usize, 65)) ==
                   roots[4] &&
               fresh.callableType(fresh.callable(roots[6])) == roots[6] &&
               fresh.erasedType(fresh.erased(roots[7])) == roots[7] &&
               fresh.callable(roots[9]).function == 117,
           "fresh imports preserve canonical factories and remapped closures");
  }
  for (auto mode : {ValidationMode::Eager, ValidationMode::OnDemand}) {
    TypeStore producer;
    ViewType view{Type::I32, ParameterMode::Read, "view"};
    auto first = producer.declareImportedType(ImportedTypeKind::View);
    auto second = producer.declareImportedType(ImportedTypeKind::View);
    producer.defineImportedType(first, view);
    producer.defineImportedType(second, view);
    auto symbols = std::make_shared<const TypeGraphSymbols>(symbolMaps());
    auto encoded =
        exportTypeGraph(producer, std::array{first, second}, *symbols, mode);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore fresh;
    auto imported =
        importTypeGraph(fresh, encoded.bytes, *symbols, mode, symbols);
    expect(static_cast<bool>(imported), imported.error);
    expect(imported.roots[0] == imported.roots[1] &&
               fresh.viewType(Type::I32, ParameterMode::Read) ==
                   imported.roots[0],
           "fresh imports still merge duplicate structural identities");
  }
  TypeStore consumer;
  consumer.declareProduct("unrelated", false);
  consumer.declareParameter("T", false);
  auto pollution = consumer.regions().binder(0, true);
  consumer.regions().bound(pollution, "unrelated");
  auto existingCount = consumer.constant(Type::Usize, 65);
  auto existingArray = consumer.arrayType(Type::I32, existingCount);
  auto existingView =
      consumer.viewType(Type::I32, ParameterMode::Read, RegionId::Static);
  auto existingSlice = consumer.sliceType(Type::I32);
  CallableType plain;
  plain.parameters = {{Type::I32, ParameterMode::Value, "different-name"}};
  plain.result = plain.abiResult = Type::I32;
  auto existingCallable = consumer.callableType(plain);
  auto symbols = symbolMaps(100);
  ErasedType simple;
  simple.name = "any core::Simple";
  simple.declaration = 107;
  auto existingErased = consumer.erasedType(simple);
  symbols.lookupDefinition =
      [&](const DefinitionIdentity &identity) -> std::optional<Type> {
    auto found = importedNames.find(identity);
    return found == importedNames.end() ? std::nullopt
                                        : std::optional(found->second);
  };
  auto imported = importTypeGraph(consumer, bytes, symbols);
  expect(static_cast<bool>(imported), imported.error);
  for (const auto &definition : imported.definitions)
    importedNames.emplace(definition.identity, definition.type);
  const auto &associatedBindings =
      consumer.erased(imported.roots[7]).associated;
  auto importedCount =
      importedNames.at(DefinitionIdentity{"core@revision", "core::Trait", 1});
  auto importedValue =
      importedNames.at(DefinitionIdentity{"core@revision", "core::Trait", 2});
  auto countBinding = std::find_if(
      associatedBindings.begin(), associatedBindings.end(),
      [&](const auto &binding) { return binding.parameter == importedCount; });
  auto valueBinding = std::find_if(
      associatedBindings.begin(), associatedBindings.end(),
      [&](const auto &binding) { return binding.parameter == importedValue; });
  expect(countBinding != associatedBindings.end() &&
             consumer.scalarConstantValue(countBinding->argument) ==
                 integerLiteral(7) &&
             valueBinding != associatedBindings.end() &&
             consumer.isConstant(valueBinding->argument) &&
             consumer.parameter(valueBinding->argument).valueType ==
                 imported.roots[0],
         "associated constant declarations and non-scalar projections must "
         "round-trip");
  auto repeated = importTypeGraph(consumer, bytes, symbols);
  expect(static_cast<bool>(repeated), repeated.error);
  expect(repeated.roots == imported.roots,
         "same logical graph must reuse type and region identities");
  const auto &r = imported.roots;
  expect(consumer.needsDrop(r[r.size() - 2]) && consumer.needsDrop(r.back()) &&
             consumer.product(r[r.size() - 2]).nativeCleanup ==
                 NativeCleanup::RefRelease &&
             consumer.product(r.back()).nativeCleanup ==
                 NativeCleanup::RefMutRelease,
         "imported cell guards must preserve their distinct release actions");
  expect(r[4] == existingArray && r[20] == existingArray &&
             r[5] == existingCount && r[14] == existingView &&
             r[15] == existingSlice && r[16] == existingCallable &&
             r[17] == existingErased,
         "import must reuse preexisting canonical structures");
  expect(consumer.arrayType(Type::I32, consumer.constant(Type::Usize, 65)) ==
                 r[4] &&
             consumer.callableType(plain) == r[16],
         "future factories must reuse imported canonical structures");
  expect(consumer.product(r[0]).destructor == 111 &&
             consumer.product(r[0]).package == 103 &&
             consumer.callable(r[9]).function == 117 &&
             consumer.erased(r[7]).declaration == 107,
         "external logical symbols must remap");
  auto instance = consumer.instantiateProduct(
      r[0], {Type::I32, consumer.constant(Type::Usize, 65), r[16]});
  expect(consumer.needsDrop(instance) && instance == r[21] && r[22] != r[1] &&
             consumer.arrayLength(consumer.product(instance).fields[1].type) ==
                 66,
         "imported generic typed count must instantiate with drop behavior");
  const auto &higher = consumer.callable(r[6]);
  auto bound = higher.regionParameters[0];
  auto intersection = consumer.view(higher.result).region;
  const auto &sources = consumer.regions().get(intersection).sources;
  expect(sources.size() == 3 &&
             consumer.regions().get(bound).binder != pollution.binder &&
             !consumer.regions().visible(bound, 0) &&
             consumer.regions().visible(bound, higher.regionUniverse),
         "higher-ranked universes and free region intersections must survive");
  auto rebound = consumer.substituteRegions(
      consumer.viewType(Type::I32, ParameterMode::Read, bound),
      std::array{RegionBinding{bound, RegionId::Static}});
  expect(rebound == existingView &&
             consumer.parameter(r[3]).callableConstraint == r[6] &&
             consumer.satisfiesCallable(r[6], r[6]) &&
             consumer.coroutineInterior(r[9]).size() == 2,
         "imported region substitution and callable constraints must operate");
  expect(consumer.callableType(higher) == r[6] &&
             consumer.erasedType(consumer.erased(r[7])) == r[7] &&
             !consumer.satisfiesCallable(
                 existingCallable, consumer.parameter(r[3]).callableConstraint),
         "future factories and callable rejection must preserve contracts");
  std::array bindings{TypeBinding{r[1], Type::I32},
                      TypeBinding{r[2], consumer.constant(Type::Usize, 65)}};
  auto pattern = consumer.product(r[0]).fields[1].type;
  auto substituted = consumer.substitute(pattern, bindings);
  expect(substituted ==
             consumer.arrayType(Type::I32, consumer.constant(Type::Usize, 66)),
         "imported generic substitution must use canonical array equality");
  auto viewPattern = consumer.callable(r[6]).parameters[0].type;
  expect(
      consumer.matchesSubstitution(
          viewPattern, consumer.viewType(Type::I32, ParameterMode::Read, bound),
          bindings) &&
          !consumer.matchesSubstitution(
              viewPattern,
              consumer.viewType(Type::Bool, ParameterMode::Read, bound),
              bindings),
      "imported regional view patterns must accept and reject substitutions");
  auto failedUnchanged = [&](const std::vector<std::uint8_t> &bad,
                             TypeGraphSymbols maps) {
    TypeStore expected = consumer;
    auto result = importTypeGraph(consumer, bad, maps);
    expect(!result && !result.error.empty(), "corrupt graph must reject");
    expect(consumer.declareProduct("probe", false) ==
               expected.declareProduct("probe", false),
           "failed import must not allocate consumer types");
    auto actualScope = consumer.regions().binder(0, true);
    auto expectedScope = expected.regions().binder(0, true);
    expect(actualScope.binder == expectedScope.binder &&
               actualScope.universe == expectedScope.universe,
           "failed import must not allocate consumer regions");
    expect(consumer.product(r[0]).destructor == 111 &&
               consumer.arrayType(Type::I32, existingCount) == existingArray,
           "failed import must preserve semantic definitions and interning");
  };
  for (auto length : {std::size_t{0}, std::size_t{7}, std::size_t{36},
                      bytes.size() / 2, bytes.size() - 1})
    failedUnchanged({bytes.begin(), bytes.begin() + length}, symbols);
  auto bad = bytes;
  bad[8] = 1;
  failedUnchanged(bad, symbols);
  bad = bytes;
  bad[12] = 32;
  failedUnchanged(bad, symbols);
  bad = bytes;
  bad[36] = 255;
  failedUnchanged(bad, symbols);
  bad = bytes;
  put32(bad, bad.size() - 4, UINT32_MAX);
  failedUnchanged(bad, symbols);
  bad = bytes;
  bad.push_back(0);
  failedUnchanged(bad, symbols);
  unsigned resolutions = 0;
  auto countResolutions = symbols;
  countResolutions.resolve = [&](SymbolKind kind, std::string_view name) {
    ++resolutions;
    return symbols.resolve(kind, name);
  };
  failedUnchanged(bad, countResolutions);
  expect(resolutions == 0,
         "malformed graph must be rejected before resolving symbols");
  bad = bytes;
  put32(bad, 16, UINT32_MAX);
  failedUnchanged(bad, symbols);
  bad = bytes;
  auto universeOffset = 36 + u32(bytes, 16);
  expect(u32(bytes, 24) > 1, "fixture needs nested universes");
  put32(bad, universeOffset + 4, 1);
  failedUnchanged(bad, symbols);
  auto unresolved = symbols;
  unresolved.resolve = [](SymbolKind,
                          std::string_view) -> std::optional<std::uint32_t> {
    return {};
  };
  failedUnchanged(bytes, unresolved);
  for (auto missing :
       {SymbolKind::Closure, SymbolKind::Interface, SymbolKind::Package}) {
    auto missingSymbol = symbols;
    missingSymbol.resolve =
        [&, missing](SymbolKind kind,
                     std::string_view name) -> std::optional<std::uint32_t> {
      return kind == missing ? std::nullopt : symbols.resolve(kind, name);
    };
    failedUnchanged(bytes, missingSymbol);
  }
  bad = bytes;
  constexpr std::string_view destructorSymbol = "0:11";
  auto destructor = std::search(
      bad.begin(), bad.end(), destructorSymbol.begin(), destructorSymbol.end());
  expect(destructor != bad.end(), "fixture needs a drop symbol");
  destructor[3] = '7';
  failedUnchanged(bad, symbols);
  bad = bytes;
  auto regionOffset = universeOffset + 4 * u32(bytes, 24) + 4 * u32(bytes, 28);
  put32(bad, regionOffset + 1, UINT32_MAX);
  failedUnchanged(bad, symbols);
  for (std::uint32_t i = 0; i < u32(bytes, 20); ++i) {
    auto nameLength = u32(bytes, regionOffset + 9);
    auto sourcesOffset = regionOffset + 13 + nameLength;
    auto count = u32(bytes, sourcesOffset);
    if (bytes[regionOffset] ==
        static_cast<unsigned>(RegionKind::Intersection)) {
      bad = bytes;
      put32(bad, sourcesOffset + 4, i + 2);
      failedUnchanged(bad, symbols);
      break;
    }
    regionOffset = sourcesOffset + 4 + 4 * count;
  }
  auto conflict = symbols;
  auto incompatible = consumer.declareProduct("wrong", false);
  conflict.lookupDefinition =
      [&](const DefinitionIdentity &) -> std::optional<Type> {
    return incompatible;
  };
  failedUnchanged(bytes, conflict);
  {
    TypeStore producer;
    auto origin = producer.declareProduct("Borrowed", true);
    auto scope = producer.regions().binder(0, true);
    auto region = producer.regions().bound(scope, "a");
    auto shell = producer.regionalShell(origin, {region}, {});
    producer.defineProduct(
        shell, {{"next", producer.pointerType(shell, ParameterMode::Read)}});
    producer.defineProduct(
        origin, {{"next", producer.pointerType(origin, ParameterMode::Read)}});
    producer.setRegionPattern(origin, shell);
    std::vector<TypeField> integers{
        {"value", producer.viewType(Type::I32, ParameterMode::Read, region)}};
    std::vector<TypeField> booleans{
        {"value", producer.viewType(Type::Bool, ParameterMode::Read, region)}};
    auto normalized =
        producer.regionalProduct(origin, integers, {region}, true);
    auto otherNormalized =
        producer.regionalProduct(origin, booleans, {region}, true);
    auto plainRegional =
        producer.regionalProduct(origin, integers, {region}, false);
    auto otherPlain =
        producer.regionalProduct(origin, booleans, {region}, false);
    CallableType descriptor;
    descriptor.function = 17;
    auto closure = producer.closureType("Closure", integers, descriptor);
    auto regionalClosure =
        producer.regionalProduct(closure, integers, {region}, false);
    producer.setCoroutineInterior(closure, {shell, normalized});
    std::vector<Type> roots{origin,          shell,          normalized,
                            otherNormalized, plainRegional,  otherPlain,
                            closure,         regionalClosure};
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{
          "pkg", type == origin ? "Borrowed" : "Closure", {}};
    };
    auto encoded = exportTypeGraph(producer, roots, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    target.declareProduct("unrelated", false);
    maps = symbolMaps(100);
    std::map<DefinitionIdentity, Type> names;
    maps.lookupDefinition =
        [&](const DefinitionIdentity &identity) -> std::optional<Type> {
      auto found = names.find(identity);
      return found == names.end() ? std::nullopt : std::optional(found->second);
    };
    auto decoded = importTypeGraph(target, encoded.bytes, maps);
    expect(static_cast<bool>(decoded), decoded.error);
    const auto &types = decoded.roots;
    expect(types[2] != types[3] && types[4] != types[5] && types[2] != types[4],
           "regional field normalizations must retain distinct identities");
    for (auto index : {1u, 2u, 3u, 4u, 5u}) {
      auto record = target.product(types[index]);
      expect(target.regionalProduct(types[0], record.fields,
                                    record.regionArguments,
                                    record.normalizedFields) == types[index],
             "regional factories must reuse restored recursive field graphs");
    }
    expect(target.callable(types[7]).environment == types[6] &&
               target.callable(types[7]).function == 117 &&
               target.coroutineInterior(types[7]) ==
                   std::vector<Type>{types[1], types[2]},
           "regional closures retain original environments and interiors");
    for (const auto &definition : decoded.definitions)
      names.emplace(definition.identity, definition.type);
    auto again = importTypeGraph(target, encoded.bytes, maps);
    expect(again && again.roots == types,
           "recursive regional patterns must reuse existing logical owners");
  }
  {
    auto make = [](TypeStore &store, bool reverse, bool collapse) {
      auto root = store.declareProduct("Owner", true);
      auto first = store.regions().binder(0, true);
      auto second = collapse ? store.regions().binder(first.universe)
                             : store.regions().binder(0, true);
      auto aScope = reverse ? second : first;
      auto bScope = reverse ? first : second;
      std::array<RegionId, 3> locals;
      for (auto &local : locals)
        local = store.regions().local(aScope);
      if (reverse)
        std::reverse(locals.begin(), locals.end());
      auto a = store.regions().intersection({locals[0], locals[1]});
      auto b = store.regions().intersection({locals[0], locals[2]});
      auto c = store.regions().intersection(
          {store.regions().local(bScope), store.regions().local(bScope)});
      store.defineProduct(
          root, {{"first", store.viewType(Type::I32, ParameterMode::Read, a)},
                 {"shared", store.viewType(Type::I32, ParameterMode::Read, b)},
                 {"other", store.viewType(Type::I32, ParameterMode::Read, c)}});
      return root;
    };
    TypeStore producer;
    auto root = make(producer, false, false);
    auto maps = symbolMaps();
    maps.definition = [](Type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", "Owner", {}};
    };
    auto encoded = exportTypeGraph(producer, std::array{root}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    target.declareProduct("unrelated", false);
    target.regions().local(target.regions().binder(0, true));
    auto original = make(target, true, false);
    maps.lookupDefinition =
        [&](const DefinitionIdentity &) -> std::optional<Type> {
      return original;
    };
    auto before = target.storedTypes();
    auto decoded = importTypeGraph(target, encoded.bytes, maps);
    expect(decoded && decoded.roots[0] == original &&
               target.storedTypes() == before,
           "unnamed intersections must alpha-remap by membership and ancestry");
    TypeStore incompatible;
    auto collapsed = make(incompatible, false, true);
    maps.lookupDefinition =
        [&](const DefinitionIdentity &) -> std::optional<Type> {
      return collapsed;
    };
    before = incompatible.storedTypes();
    auto rejected = importTypeGraph(incompatible, encoded.bytes, maps);
    expect(!rejected && incompatible.storedTypes() == before,
           "different universes must not collapse during logical reuse");
  }
  {
    TypeStore producer;
    auto parameter = producer.declareParameter("renamed", true);
    auto maps = symbolMaps();
    maps.definition = [](Type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", "Owner", 0};
    };
    auto encoded = exportTypeGraph(producer, std::array{parameter}, maps);
    TypeStore target;
    auto original = target.declareParameter("T", true);
    maps.lookupDefinition =
        [&](const DefinitionIdentity &) -> std::optional<Type> {
      return original;
    };
    auto decoded = importTypeGraph(target, encoded.bytes, maps);
    expect(decoded && decoded.roots[0] == original,
           "generic logical identity must not depend on parameter spelling");
  }
  {
    TypeStore producer;
    producer.setPointerBits(32);
    auto count = producer.constant(Type::Usize, 65);
    auto array = producer.arrayType(Type::I32, count);
    auto minimum = producer.constant(Type::I128, integerMinimum(Type::I128));
    auto encoded = exportTypeGraph(producer, std::array{array, count, minimum},
                                   symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    target.setPointerBits(32);
    target.declareProduct("unrelated", false);
    auto decoded = importTypeGraph(target, encoded.bytes, symbolMaps());
    expect(
        decoded &&
            decoded.roots[0] ==
                target.arrayType(Type::I32, target.constant(Type::Usize, 65)) &&
            decoded.roots[1] == target.constant(Type::Usize, 65),
        "32-bit targets must preserve typed counts and canonical arrays");
    auto next = target.constantExpression(
        "+", {decoded.roots[2], target.constant(Type::I128, 1)});
    expect(target.scalarConstantValue(next) ==
               evaluateIntegerConstant("+", Type::I128,
                                       integerMinimum(Type::I128),
                                       integerLiteral(1), 32),
           "imported 128-bit constants must retain exact arithmetic");
    failedUnchanged(encoded.bytes, symbols);
  }
  {
    TypeStore producer;
    auto deep = Type::I32;
    for (unsigned i = 0; i < 129; ++i)
      deep = producer.structural(AggregateKind::Tuple, {deep});
    auto encoded = exportTypeGraph(producer, std::array{deep}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    failedUnchanged(encoded.bytes, symbols);
  }
  {
    TypeStore producer;
    auto invalid = producer.declareImportedType(ImportedTypeKind::Parameter);
    TypeParameter parameter;
    parameter.kind = TypeParameterKind::Value;
    parameter.valueType = Type::F32;
    parameter.numeric = integerLiteral(1);
    producer.defineImportedType(invalid, parameter);
    auto encoded = exportTypeGraph(producer, std::array{invalid}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    failedUnchanged(encoded.bytes, symbols);
  }
  {
    TypeStore producer;
    auto origin = producer.declareProduct("Generic", false);
    auto parameter = producer.declareParameter("T", false);
    producer.setGenericParameters(origin, {parameter});
    auto invalid =
        producer.instantiateProduct(origin, {producer.constant(Type::I32, 1)});
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      if (type == origin)
        return DefinitionIdentity{"pkg", "Generic", {}};
      if (type == parameter)
        return DefinitionIdentity{"pkg", "Generic", 0};
      return {};
    };
    auto encoded = exportTypeGraph(producer, std::array{invalid}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    auto rejected = importTypeGraph(target, encoded.bytes, maps);
    expect(!rejected &&
               rejected.error == "invalid generic product type argument",
           "generic product metadata must preserve argument kind");
  }
  {
    TypeStore producer;
    auto payload = producer.declareProduct("Payload", false);
    auto origin = producer.declareProduct("Generic", false);
    auto parameter = producer.declareConstParameter("N", payload);
    producer.setGenericParameters(origin, {parameter});
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      if (type == payload)
        return DefinitionIdentity{"pkg", "Payload", {}};
      if (type == origin)
        return DefinitionIdentity{"pkg", "Generic", {}};
      if (type == parameter)
        return DefinitionIdentity{"pkg", "Generic", 0};
      return {};
    };
    auto encoded = exportTypeGraph(producer, std::array{origin}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    auto rejected = importTypeGraph(target, encoded.bytes, maps);
    expect(!rejected &&
               rejected.error ==
                   "generic const parameter requires a supported scalar type",
           "generic const metadata must retain its scalar type restriction");
  }
  {
    TypeStore producer;
    auto count = producer.declareConstParameter("COUNT", Type::I32);
    ErasedType erased;
    erased.name = "any core::Trait";
    erased.declaration = 7;
    erased.associated = {{count, producer.constant(Type::Bool, true)}};
    auto root = producer.erasedType(erased);
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      if (type == count)
        return DefinitionIdentity{"pkg", "Trait", 0};
      return {};
    };
    auto encoded = exportTypeGraph(producer, std::array{root}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    auto rejected = importTypeGraph(target, encoded.bytes, maps);
    expect(!rejected && rejected.error ==
                            "erased associated constant value type mismatch",
           "erased associated constants must match concrete scalar types");
  }
  {
    TypeStore producer;
    auto first = producer.callableType(plain);
    auto otherAbi = plain;
    otherAbi.abiResult = Type::U64;
    auto second = producer.callableType(otherAbi);
    expect(first != second, "callable ABI results participate in identity");
    auto encoded =
        exportTypeGraph(producer, std::array{first, second}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    auto abi = importTypeGraph(consumer, encoded.bytes, symbols);
    expect(abi && abi.roots[0] == existingCallable &&
               abi.roots[1] != existingCallable &&
               consumer.callable(abi.roots[1]).abiResult == Type::U64,
           "imported ABI result contracts must not collapse");
  }
  {
    TypeStore types;
    std::array ids{types.declareImportedType(ImportedTypeKind::Callable),
                   types.declareImportedType(ImportedTypeKind::Callable),
                   types.declareImportedType(ImportedTypeKind::Callable)};
    std::array<std::size_t, 3> loaded{};
    std::array<CallableType, 3> descriptors{plain, plain, plain};
    std::array<ImportedTypeIndex, 3> index{};
    auto scope = types.regions().binder();
    auto other = types.regions().binder();
    auto first = types.regions().inference(scope);
    auto second = types.regions().inference(scope);
    std::array key{plain.result, plain.error, plain.parameters.front().type};
    for (std::size_t i = 0; i < descriptors.size(); ++i) {
      descriptors[i].regionUniverse = i == 2 ? other.universe : scope.universe;
      descriptors[i].parameterRegions = {i == 0 ? first : second};
      index[i].key = key;
      index[i].regionUniverse = descriptors[i].regionUniverse;
      index[i].callableParameterRegions = descriptors[i].parameterRegions;
    }
    auto loader = std::make_shared<const TypeStore::ImportedDefinitionLoader>(
        [descriptors, &loaded](std::size_t i) -> ImportedTypeDefinition {
          ++loaded.at(i);
          return descriptors.at(i);
        });
    types.deferImportedDefinitions(ids, index, loader);
    expect(types.callableType(descriptors[1]) == ids[1] && loaded[0] == 0 &&
               loaded[1] == 1 && loaded[2] == 0,
           "callable lookup must not decode unrelated region identities");
  }
  {
    TypeStore producer;
    auto first = producer.structural(AggregateKind::Tuple, {Type::I32});
    auto duplicate = producer.declareImportedType(ImportedTypeKind::Product);
    auto definition = producer.importedDefinition(first);
    auto &product = std::get<ImportedProduct>(definition).descriptor;
    product.copyRequested = !product.copyRequested;
    producer.defineImportedType(duplicate, std::move(definition));
    auto encoded =
        exportTypeGraph(producer, std::array{first, duplicate}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    auto rejected = importTypeGraph(target, encoded.bytes, symbolMaps());
    expect(!rejected && rejected.error ==
                            "conflicting logical or structural type definition",
           "colliding structural identities must retain all their contracts");
  }
  {
    std::uint32_t state = 0x13579bdu;
    auto before = consumer.storedTypes();
    for (unsigned mutation = 0; mutation < 256; ++mutation) {
      state = state * 1664525u + 1013904223u;
      auto changed = bytes;
      auto position = static_cast<std::size_t>(state) % changed.size();
      changed[position] ^= static_cast<std::uint8_t>(1u << (state >> 29));
      TypeStore trial = consumer;
      auto decoded = importTypeGraph(trial, changed, symbols);
      if (!decoded)
        expect(trial.storedTypes() == before &&
                   trial.product(r[0]).destructor == 111,
               "mutation rejection must leave semantic store unchanged");
    }
  }
  {
    auto encodeOrder = [](bool reverse) {
      TypeStore producer;
      if (reverse) {
        producer.declareProduct("unrelated", false);
        producer.declareParameter("T", false);
        auto scope = producer.regions().binder(0, true);
        producer.regions().local(scope);
      }
      auto first = producer.declareProduct(reverse ? "B" : "A", false);
      auto second = producer.declareProduct(reverse ? "A" : "B", false);
      auto a = reverse ? second : first;
      auto b = reverse ? first : second;
      producer.defineProduct(
          a, {{"b", producer.pointerType(b, ParameterMode::Read)}});
      producer.defineProduct(
          b, {{"a", producer.pointerType(a, ParameterMode::Read)}});
      auto maps = symbolMaps();
      maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
        return DefinitionIdentity{"pkg", std::string(producer.name(type)), {}};
      };
      return exportTypeGraph(producer, std::array{a, b}, maps);
    };
    auto forward = encodeOrder(false);
    auto reverse = encodeOrder(true);
    expect(forward && reverse && forward.bytes == reverse.bytes,
           "logical structural archive must not depend on allocation order");
  }
  {
    TypeStore producer;
    auto pointer = producer.pointerType(Type::I32, ParameterMode::Read);
    auto encoded = exportTypeGraph(producer, std::array{pointer}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    put32(encoded.bytes, 42, builtinTypeCount);
    failedUnchanged(encoded.bytes, symbols);
  }
  {
    TypeStore producer;
    auto a = producer.declareProduct("One", false);
    auto b = producer.declareProduct("Two", false);
    producer.defineProduct(a, {{"value", Type::I32}});
    producer.defineProduct(b, {{"first", Type::I64}, {"second", Type::Bool}});
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", type == a ? "One" : "Two", {}};
    };
    for (auto mode : {ValidationMode::Eager, ValidationMode::OnDemand}) {
      auto encoded = exportTypeGraph(producer, std::array{a, b}, maps, mode);
      expect(static_cast<bool>(encoded), encoded.error);
      constexpr std::string_view two = "Two";
      auto found = std::search(encoded.bytes.begin(), encoded.bytes.end(),
                               two.begin(), two.end());
      expect(found != encoded.bytes.end(), "duplicate identity fixture");
      std::copy_n("One", 3, found);
      failedUnchanged(encoded.bytes, symbols);
      TypeStore fresh;
      auto retained = std::make_shared<const TypeGraphSymbols>(maps);
      auto imported =
          importTypeGraph(fresh, encoded.bytes, *retained, mode, retained);
      expect(
          !imported &&
              imported.error == "duplicate logical definition identity",
          "duplicate logical identities must reject across different payloads");
    }
    producer.defineProduct(a, {{"self", a}});
    auto cyclic = exportTypeGraph(producer, std::array{a}, maps);
    expect(static_cast<bool>(cyclic), cyclic.error);
    failedUnchanged(cyclic.bytes, symbols);
  }
  {
    TypeStore producer;
    auto parameter = producer.declareParameter("T", false);
    auto hidden = producer.declareParameter("Q", false);
    auto opaque = producer.opaqueType("Hidden", hidden, {}, false);
    producer.setGenericParameters(opaque, {parameter});
    auto integer =
        producer.substitute(opaque, std::array{TypeBinding{hidden, Type::I32}});
    auto boolean = producer.substitute(
        opaque, std::array{TypeBinding{hidden, Type::Bool}});
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      if (type == opaque)
        return DefinitionIdentity{"pkg", "Hidden", {}};
      return DefinitionIdentity{
          "pkg", type == parameter ? "HiddenOwner" : "OuterOwner", 0};
    };
    auto encoded =
        exportTypeGraph(producer, std::array{integer, boolean}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    target.declareProduct("unrelated", false);
    auto actualHidden = target.declareParameter("Q", false);
    auto actualParameter = target.declareParameter("T", false);
    auto actualOpaque = target.opaqueType("Hidden", actualHidden, {}, false);
    target.setGenericParameters(actualOpaque, {actualParameter});
    auto existing = target.substitute(
        actualOpaque, std::array{TypeBinding{actualHidden, Type::I32}});
    maps.lookupDefinition =
        [&](const DefinitionIdentity &identity) -> std::optional<Type> {
      if (identity.definition == "Hidden")
        return actualOpaque;
      return identity.definition == "HiddenOwner" ? actualParameter
                                                  : actualHidden;
    };
    auto decoded = importTypeGraph(target, encoded.bytes, maps);
    expect(static_cast<bool>(decoded), decoded.error);
    expect(decoded.roots[0] == existing && decoded.roots[1] != existing &&
               target.substitute(
                   actualOpaque,
                   std::array{TypeBinding{actualHidden, Type::Bool}}) ==
                   decoded.roots[1],
           "opaque identities include substituted hidden fields and bounds");
  }
  {
    TypeStore producer;
    auto origin = producer.declareProduct("Cycle", false);
    auto record =
        std::get<ImportedProduct>(producer.importedDefinition(origin));
    record.descriptor.regionOrigin = origin;
    producer.defineImportedType(origin, record);
    auto encoded = exportTypeGraph(producer, std::array{origin}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    failedUnchanged(encoded.bytes, symbols);
    ErasedType descriptor;
    descriptor.declaration = 7;
    auto erased = producer.erasedType(descriptor);
    producer.setErasedParents(erased, {erased});
    encoded = exportTypeGraph(producer, std::array{erased}, symbolMaps());
    expect(static_cast<bool>(encoded), encoded.error);
    failedUnchanged(encoded.bytes, symbols);
  }
  {
    TypeStore producer;
    auto drop = producer.declareProduct("Drop", false);
    producer.setDestructor(drop, 11);
    CallableType descriptor;
    descriptor.function = 11;
    auto closure = producer.closureType("Closure", {}, descriptor);
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", std::string(producer.name(type)), {}};
    };
    auto encoded = exportTypeGraph(producer, std::array{drop, closure}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    TypeStore target;
    target.declareProduct("unrelated", false);
    auto receiver = symbolMaps(100);
    auto resolve = receiver.resolve;
    receiver.resolve =
        [resolve](SymbolKind kind,
                  std::string_view name) -> std::optional<std::uint32_t> {
      if (kind == SymbolKind::Closure)
        return name == symbolName(kind, 11) ? std::optional{211u}
                                            : std::nullopt;
      return resolve(kind, name);
    };
    auto decoded = importTypeGraph(target, encoded.bytes, receiver);
    expect(static_cast<bool>(decoded), decoded.error);
    expect(target.product(decoded.roots[0]).destructor == 111 &&
               target.needsDrop(decoded.roots[0]) &&
               target.callable(decoded.roots[1]).function == 211,
           "equal producer function and closure ordinals use distinct domains");
    receiver.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", std::string(target.name(type)), {}};
    };
    receiver.symbol = [](SymbolKind kind,
                         std::uint32_t index) -> std::optional<std::string> {
      auto offset = kind == SymbolKind::Closure ? 200u : 100u;
      return index < offset ? std::nullopt
                            : std::optional(symbolName(kind, index - offset));
    };
    auto reencoded = exportTypeGraph(target, decoded.roots, receiver);
    expect(reencoded && reencoded.bytes == encoded.bytes,
           "closure and function identities survive independent remapping");
  }
  std::cout << "portable type/region graph passed\n";
}
