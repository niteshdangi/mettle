#include "metadata/type_graph.h"
#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <map>
#include <string>

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
  std::vector<std::uint8_t> bytes;
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
    ErasedType trait;
    trait.name = "any core::Trait<T>";
    trait.declaration = 7;
    trait.arguments = {t};
    trait.associated = {{associated, t}};
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
    ErasedType simple;
    simple.name = "any core::Simple";
    simple.declaration = 7;
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
        producer.erasedType(simple),
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
    producer.setNativeCleanup(roots.back(), NativeCleanup::RefMutRelease);
    symbols.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      auto found = identities.find(type);
      return found == identities.end() ? std::nullopt
                                       : std::optional(found->second);
    };
    auto encoded = exportTypeGraph(producer, roots, symbols);
    expect(static_cast<bool>(encoded), encoded.error);
    bytes = std::move(encoded.bytes);
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
  auto repeated = importTypeGraph(consumer, bytes, symbols);
  expect(static_cast<bool>(repeated), repeated.error);
  expect(repeated.roots == imported.roots,
         "same logical graph must reuse type and region identities");
  const auto &r = imported.roots;
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
    auto maps = symbolMaps();
    maps.definition = [&](Type type) -> std::optional<DefinitionIdentity> {
      return DefinitionIdentity{"pkg", type == a ? "One" : "Two", {}};
    };
    auto encoded = exportTypeGraph(producer, std::array{a, b}, maps);
    expect(static_cast<bool>(encoded), encoded.error);
    constexpr std::string_view two = "Two";
    auto found = std::search(encoded.bytes.begin(), encoded.bytes.end(),
                             two.begin(), two.end());
    expect(found != encoded.bytes.end(), "duplicate identity fixture");
    std::copy_n("One", 3, found);
    failedUnchanged(encoded.bytes, symbols);
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
