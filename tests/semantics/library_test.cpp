#include "ir/codec.h"
#include "ir/verify.h"
#include "lowering/scalar.h"
#include "metadata/type_graph.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "semantics/check.h"
#include "semantics/library.h"
#include "syntax/parser.h"
#include <algorithm>
#include <array>
#include <barrier>
#include <iostream>
#include <map>
#include <sstream>
#include <thread>

namespace {
int failures = 0;
void expect(bool value, const char *message) {
  if (!value) {
    std::cerr << "FAILED: " << message << '\n';
    ++failures;
  }
}
void errors(const mettle::Diagnostics &diagnostics) {
  for (const auto &item : diagnostics.items)
    std::cerr << item.phase << "@" << item.span.begin << ": " << item.message
              << '\n';
}
void interfaceSnapshots() {
  using namespace mettle;
  interfaces::Database imported;
  imported.definitions.push_back({});
  imported.definitions[0].name = "Original";
  imported.projections.push_back({Type::I32, Type::I64, Type::Unit, 0});
  imported.callableContracts[Type::I32] = Type::I64;
  imported.callableContracts[Type::U32] = Type::U64;
  imported.callableContracts.freeze();
  imported.unpinImplementations[Type::I32].target = Type::I32;
  imported
      .structuralDeclarations[{interfaces::Property::Transferable, Type::I32}]
      .implementation.target = Type::I32;
  imported.unpinImplementations.freeze();
  imported.structuralDeclarations.freeze();
  auto consumer = imported;
  consumer.definitions[0].name = "Consumer";
  consumer.projections[0].subject = Type::Bool;
  consumer.callableContracts[Type::I32] = Type::U8;
  consumer.callableContracts[Type::Bool] = Type::Unit;
  consumer.unpinImplementations[Type::I32].target = Type::I64;
  consumer
      .structuralDeclarations[{interfaces::Property::Transferable, Type::I32}]
      .negative = true;
  const auto &original = imported;
  expect(original.definitions[0].name == "Original" &&
             original.projections[0].subject == Type::I64 &&
             original.callableContracts.at(Type::I32) == Type::I64 &&
             !original.callableContracts.contains(Type::Bool) &&
             original.unpinImplementations.at(Type::I32).target == Type::I32 &&
             !original.structuralDeclarations
                  .at({interfaces::Property::Transferable, Type::I32})
                  .negative,
         "consumer interface edits preserve the immutable imported phase");
  std::map<Type, Type> expected(original.callableContracts.begin(),
                                original.callableContracts.end());
  expected[Type::I32] = Type::U8;
  expected[Type::Bool] = Type::Unit;
  auto added = consumer.callableContracts.emplace(Type::Char, Type::U16);
  expected[Type::Char] = Type::U16;
  auto inherited = consumer.callableContracts.emplace(Type::U32, Type::Bool);
  auto overridden = consumer.callableContracts.emplace(Type::I32, Type::Unit);
  expect(added.second && !inherited.second && !overridden.second &&
             inherited.first->second == Type::U64 &&
             overridden.first->second == Type::U8 &&
             consumer.callableContracts.find(Type::Unit) ==
                 consumer.callableContracts.end() &&
             std::equal(added.first, consumer.callableContracts.end(),
                        expected.find(Type::Char), expected.end()),
         "overlay insertion preserves inherited overrides and merged suffixes");
  expect(consumer.callableContracts.size() == expected.size() &&
             std::equal(consumer.callableContracts.begin(),
                        consumer.callableContracts.end(), expected.begin(),
                        expected.end()),
         "interface overlays merge new, overridden and untouched contracts");
  auto position = consumer.callableContracts.find(expected.begin()->first);
  expect(std::equal(position, consumer.callableContracts.end(),
                    expected.begin(), expected.end()),
         "interface contract lookup retains ordered overlay traversal");
}
} // namespace

int main() {
  interfaceSnapshots();
  using namespace mettle;
  using metadata::SymbolKind;
  std::string source = R"(
pub module core {
    const BASE: i32 = 4;
    interface ConstValue { static fn value(x: i32): i32; }
    extend i32 implements ConstValue {
        static const fn value(x: i32): i32 { x }
    }
    const fn dispatched<T: ConstValue>(x: i32): i32 {
        T.(ConstValue).value(x)
    }
    type RuntimeProvider {}
    extend RuntimeProvider implements ConstValue {
        static fn value(x: i32): i32 { x }
    }
    pub const fn runtimeValue(): i32 { dispatched<RuntimeProvider>(7) }
    const fn hidden(x: i32): i32 {
        let intermediate = dispatched<i32>(x);
        intermediate + BASE
    }
    pub const fn answer(x: i32 = hidden(2)): i32 { hidden(x) }
    pub fn identity<T>(take value: T): T { value }
    pub const fn constIdentity<T: Copy>(value: T): T { value }
    pub fn add(x: i32 = hidden(3)): i32 { x + 1 }
    static CACHED: i32 = 7;
    pub fn cached(): i32 { CACHED }
    pub fn rangeShapes(read values: [i32]): usize {
        values[..].len() + values[1usize..].len() +
            values[..2usize].len() + values[0usize..=1usize].len()
    }
    pub interface Family {
        type Item<T: Copy>: Copy;
        const FLAG: bool;
    }
    pub copy type Address { pub bits: u32 }
    extend Address {
        pub const ORIGIN: Address = Address(2130706433u32)
        pub const ALIAS: Address = Self.ORIGIN
    }
    pub module network {}
    pub const fn address(): Address { Address.ORIGIN }
    pub copy type Address6 { pub octets: [u8;16] }
    extend Address6 {
        pub const LOCALHOST: Address6 = Address6([0u8,0u8,0u8,0u8,0u8,0u8,0u8,0u8,
                      0u8,0u8,0u8,0u8,0u8,0u8,0u8,1u8])
        pub const UNSPECIFIED: Address6 = Address6([0u8;16usize])
    }
    pub const fn address6(): Address6 { Address6.LOCALHOST }
    pub type Number {}
    pub type Owned {}
    pub type Choice<T> { pub value: i32 }
    extend<T: Copy> Choice<T> {
        pub init(value: i32) { self.value = value }
    }
    extend Choice<Owned> {
        pub init(value: i32) { self.value = value + 1 }
    }
    pub type DormantConstructor {
        pub value: i32
        pub init(value: i32) { self.value = value }
    }
    pub const fn record(): Number { Number() }
    pub copy enum Marker { First, Last }
    unsafe extend Number implements Unpin {}
    unsafe extend Marker implements Transferable {}
    pub const fn mark(): Marker { Marker.Last }
    pub interface Value { fn get(): i32; }
    extend Number implements Value { fn get(): i32 { 5 } }
    pub interface Dormant { fn unused(): i32; }
    extend Marker implements Dormant { fn unused(): i32 { 0 } }
    pub interface Cursor { type Item; mut fn next(): Self.Item?; }
    pub type GenericOwner<T> { value: T }
    pub type Payload { value: i32 }
    extend<T> GenericOwner<T> {
        pub const CACHED: Payload = Payload(1)
    }
    pub type Borrowed<region r> { value: read i32 from r }
    extend<region r> Borrowed<region r> implements Cursor {
        type Item = i32
        mut fn next(): i32? { present(*self.value) }
    }
    pub fn borrow<region r>(read value: i32 from r): Borrowed<region r> {
        Borrowed(read value)
    }
    pub type Mapper<F> { callback: F }
    extend<F: mut fn(): i32> Mapper<F> implements Cursor {
        type Item = i32
        mut fn next(): i32? { present(self.callback()) }
    }
    pub fn mapper<F: mut fn(): i32>(take callback: F): Mapper<F> {
        Mapper(callback)
    }
    pub fn opaque(): some Value { Number() }
    pub fn erased(read value: any Value): i32 { value.get() }
    pub fn dispatch(): i32 { opaque().get() }
    extend Number implements Family {
        type Item<T: Copy> = (T, T)
        const FLAG = true
    }
    pub fn duplicate<T: Copy>(value: T): Number.(Family).Item<T> {
        (value, value)
    }
    pub fn preserve<region r>(
        take value: (read i32 from r)
    ): read i32 from r { value }
    pub fn apply(value: i32): i32 {
        let next = fn(item: i32): i32 { item + 1 };
        next(value)
    }
}
import core as bootstrapOnly;
)";
  std::string dormant;
  for (std::size_t i = 0; i < 511; ++i)
    dormant += "\n    fn archivedUnused" + std::to_string(i) + "(): i32 { 0 }";
  dormant += "\n    @link(\"archive-only\") extern \"C\" { "
             "unsafe fn archivedUnused511(): i32; }";
  source.insert(source.rfind("\n}\nimport core as bootstrapOnly;"), dormant);
  const Source reexportSource{"reexport.mt", "pub import super.Address;\n", 1};
  Diagnostics diagnostics;
  auto tree = parse({"library.mt", source}, diagnostics);
  auto reexports = parse(reexportSource, diagnostics);
  if (!diagnostics.empty() || reexports.imports.size() != 1) {
    errors(diagnostics);
    expect(false, "public reexport fixture parses");
    return 1;
  }
  auto reexport = std::move(reexports.imports.front());
  reexport.item.scope = {"core", "network"};
  tree.imports.push_back(std::move(reexport));
  auto checked = check(std::move(tree), diagnostics, false);
  if (!checked) {
    errors(diagnostics);
    expect(false, "source library checks");
    return 1;
  }
  auto symbolic = lowering::lower(*checked, diagnostics);
  for (bool sourceFirst : {false, true}) {
    auto database = checked->interfaceDatabase();
    auto rules = std::move(database.implementations);
    auto conflict = std::as_const(rules).front();
    conflict.checkedImport = false;
    if (sourceFirst)
      database.implementations.push_back(conflict);
    for (auto rule : rules) {
      rule.checkedImport = true;
      database.implementations.push_back(std::move(rule));
    }
    if (!sourceFirst)
      database.implementations.push_back(std::move(conflict));
    TypeStore types(*checked->typeStore());
    Diagnostics conflicts;
    interfaces::Solver solver(types, database, conflicts);
    expect(!solver.coherent() && !conflicts.empty(),
           "coherence checks source/import conflicts in either ordering");
  }
  symbolic.requireEntry = false;
  auto typesForAdapters =
      std::const_pointer_cast<TypeStore>(checked->typeStore());
  lowering::opaqueAdapters(symbolic, *typesForAdapters,
                           checked->interfaceDatabase(), diagnostics);
  lowering::erasedAdapters(symbolic, *typesForAdapters,
                           checked->interfaceDatabase());
  const auto adapterCount = symbolic.opaqueAdapters.size();
  const auto adaptedFunctionCount = symbolic.functions.size();
  expect(adapterCount >= 2, "fixture creates real opaque and erased adapters");
  lowering::opaqueAdapters(symbolic, *typesForAdapters,
                           checked->interfaceDatabase(), diagnostics);
  lowering::erasedAdapters(symbolic, *typesForAdapters,
                           checked->interfaceDatabase());
  expect(symbolic.opaqueAdapters.size() == adapterCount &&
             symbolic.functions.size() == adaptedFunctionCount,
         "existing symbolic adapter metadata is reused without new helpers");
  expect(ir::verify(symbolic, diagnostics), "source symbolic IR verifies");
  if (!diagnostics.empty())
    errors(diagnostics);
  std::map<Type, metadata::DefinitionIdentity> definitions;
  auto inventory = declarationInventory(*checked);
  for (const auto &type : inventory.types)
    definitions.emplace(type.type,
                        metadata::DefinitionIdentity{"library", type.definition,
                                                     type.parameterOrdinal});
  std::map<std::pair<SymbolKind, std::uint32_t>, std::string> symbols;
  for (const auto &symbol : inventory.symbols)
    symbols.emplace(std::pair{symbol.kind, symbol.index},
                    symbol.kind == SymbolKind::Package ? "package-library"
                                                       : symbol.definition);
  for (std::size_t i = 0; i < symbolic.functions.size(); ++i)
    symbols.emplace(std::pair{SymbolKind::Function, std::uint32_t(i)},
                    symbolic.functions[i].name);
  for (std::size_t i = 0; i < symbolic.statics.size(); ++i)
    symbols.emplace(std::pair{SymbolKind::Static, std::uint32_t(i)},
                    symbolic.statics[i].name);
  for (std::size_t i = 0; i < symbolic.closureFunctions.size(); ++i)
    symbols[std::pair{SymbolKind::Function,
                      std::uint32_t(symbolic.closureFunctions[i])}] =
        "closure-body:" + symbols.at({SymbolKind::Closure, std::uint32_t(i)});
  std::vector<Type> roots;
  std::map<Type, std::uint32_t> typeIndices;
  metadata::EncodeReferences encode;
  encode.type = [&](Type type) -> std::optional<std::uint32_t> {
    auto [found, inserted] =
        typeIndices.emplace(type, static_cast<std::uint32_t>(roots.size()));
    if (inserted)
      roots.push_back(type);
    return found->second;
  };
  encode.source = [&](Span span) -> std::optional<metadata::SourceReference> {
    if (span.source == reexportSource.id &&
        span.end <= reexportSource.text.size())
      return metadata::SourceReference{"reexport-revision",
                                       std::uint32_t(span.begin),
                                       std::uint32_t(span.end)};
    if (span.source != 0 || span.end > source.size())
      return std::nullopt;
    return metadata::SourceReference{
        "library-revision", std::uint32_t(span.begin), std::uint32_t(span.end)};
  };
  encode.symbol = [&](SymbolKind kind,
                      std::uint32_t index) -> std::optional<std::string> {
    auto found = symbols.find({kind, index});
    return found == symbols.end() ? std::nullopt : std::optional(found->second);
  };
  const std::array<SourceId, 1> bootstrapSources{0};
  auto declarations =
      exportLibraryDeclarations(*checked, encode, bootstrapSources);
  if (!declarations)
    std::cerr << declarations.error << '\n';
  expect(bool(declarations), "checked declaration export succeeds");
  auto programBytes = ir::encodeProgram(symbolic, encode);
  if (!programBytes)
    std::cerr << programBytes.error << '\n';
  expect(bool(programBytes), "symbolic bodies export");
  metadata::TypeGraphSymbols graphSymbols;
  graphSymbols.definition =
      [&](Type type) -> std::optional<metadata::DefinitionIdentity> {
    auto found = definitions.find(type);
    if (found == definitions.end())
      std::cerr << "missing fixture type identity: "
                << checked->typeStore()->name(type) << " [" << type.index()
                << "]\n";
    return found == definitions.end() ? std::nullopt
                                      : std::optional(found->second);
  };
  graphSymbols.symbol = encode.symbol;
  auto graph =
      metadata::exportTypeGraph(*checked->typeStore(), roots, graphSymbols);
  if (!graph)
    std::cerr << graph.error << '\n';
  expect(bool(graph), "shared type graph exports declaration and IR roots");
  if (!declarations || !programBytes || !graph)
    return 1;
  const auto sourceFunctionCount = checked->syntax().functions.size();
  std::string dormantMethod;
  for (std::size_t i = 0; i < sourceFunctionCount; ++i) {
    const auto &function = checked->syntax().functions[i];
    if (function.implementation < 0)
      continue;
    const auto &symbol =
        symbols.at({SymbolKind::Function, static_cast<std::uint32_t>(i)});
    if (symbol.find("unused") != std::string::npos)
      dormantMethod = symbol;
  }
  std::vector<std::pair<std::size_t, std::size_t>> defaultOwners;
  for (std::size_t i = 0; i < sourceFunctionCount; ++i)
    for (std::size_t p = 0;
         p < checked->syntax().functions[i].parameters.size(); ++p)
      if (checked->hasDefault(i, p))
        defaultOwners.emplace_back(i, p);
  std::array<std::map<std::string, std::vector<std::size_t>>, 2>
      expectedImplementations;
  std::vector<std::uint8_t> selectionRecord;
  std::uint32_t foreignCandidate = 0;
  std::size_t phase = 0;
  for (const auto *database : {&checked->declarations()->checkingDatabase,
                               &checked->declarations()->database}) {
    auto &groups = expectedImplementations[phase++];
    for (std::size_t i = 0; i < database->implementations.size(); ++i) {
      auto type = database->implementations[i].interfaceType;
      if (checked->typeStore()->isErased(type)) {
        auto owner = checked->typeStore()->erasedDeclaration(type);
        groups[std::string(database->definitionName(owner))].push_back(i);
      }
    }
    for (std::uint32_t owner = 0; owner < database->definitions.size();
         ++owner) {
      auto found = groups.find(std::string(database->definitionName(owner)));
      if (!selectionRecord.empty() || found == groups.end() ||
          found->second.size() < 2 ||
          found->second.back() + 1 >= database->implementations.size())
        continue;
      auto logical = symbols.at({SymbolKind::Interface, owner});
      expect(logical.size() < 128 && found->second.size() < 32,
             "candidate corruption fixture fits single-byte framing");
      selectionRecord.push_back(static_cast<std::uint8_t>(logical.size()));
      selectionRecord.insert(selectionRecord.end(), logical.begin(),
                             logical.end());
      selectionRecord.push_back(
          static_cast<std::uint8_t>(found->second.size() * 4));
      for (auto index : found->second)
        for (unsigned byte = 0; byte < 4; ++byte)
          selectionRecord.push_back(
              static_cast<std::uint8_t>(index >> (byte * 8)));
      foreignCandidate =
          static_cast<std::uint32_t>(database->implementations.size() - 1);
    }
  }
  checked.reset();
  symbolic = {};

  metadata::DecodeReferences decode;
  decode.source =
      [](const metadata::SourceReference &reference) -> std::optional<Span> {
    if (reference.revision == "reexport-revision")
      return Span{reference.begin, reference.end, 43};
    if (reference.revision != "library-revision")
      return std::nullopt;
    return Span{reference.begin, reference.end, 42};
  };
  resolution::Library library;
  std::size_t headerReads = 0;
  auto headerStorage =
      std::make_shared<const std::vector<std::uint8_t>>(declarations.header);
  std::weak_ptr<const std::vector<std::uint8_t>> headerLifetime = headerStorage;
  std::optional<LibraryHeaderImport> retainedHeader;
  std::size_t sourceBindings = 0;
  metadata::DecodeReferences headerReferences;
  headerReferences.sourceRange =
      [&](std::string_view revision) -> std::optional<Span> {
    ++sourceBindings;
    if (revision == "library-revision")
      return Span{0, source.size(), 42};
    if (revision == "reexport-revision")
      return Span{0, reexportSource.text.size(), 43};
    return std::nullopt;
  };
  auto makeHeader = [&]() -> std::optional<Module> {
    ++headerReads;
    library.compiledSourcePackages.emplace(42, "library");
    library.compiledSourceModules.emplace(42, std::vector<std::string>{"core"});
    library.compiledSourcePackages.emplace(43, "library");
    library.compiledSourceModules.emplace(
        43, std::vector<std::string>{"core", "network"});
    if (!retainedHeader) {
      retainedHeader =
          decodeLibraryHeader(*headerStorage, headerReferences, headerStorage);
      headerStorage.reset();
      expect(!headerLifetime.expired() && sourceBindings == 2,
             "deferred syntax retains backing and binds each revision once");
    }
    if (!*retainedHeader)
      std::cerr << retainedHeader->error << '\n';
    return std::move(copyLibraryHeader(*retainedHeader).module);
  };
  library.compiled.push_back({"core", makeHeader});
  std::size_t reads = 0;
  auto provider = [&](const std::string &) -> std::optional<Source> {
    ++reads;
    return std::nullopt;
  };
  Diagnostics unusedDiagnostics;
  auto unused = resolution::load({"unused.mt", "fn main(): i32 { 0 }\n"},
                                 provider, unusedDiagnostics, library);
  expect(bool(unused) && unusedDiagnostics.empty() && headerReads == 0 &&
             reads == 0,
         "unused native declarations are neither loaded nor checked");
  Diagnostics shadowDiagnostics;
  auto shadow = resolution::load({"shadow.mt", R"(
module core { pub fn ownValue(): i32 { 3 } }
fn main(): i32 { core.ownValue() }
)"},
                                 provider, shadowDiagnostics, library);
  expect(bool(shadow) && shadowDiagnostics.empty() && headerReads == 0 &&
             reads == 0,
         "a user core module shadows the compiled native provider");
  if (!shadowDiagnostics.empty())
    errors(shadowDiagnostics);
  auto consumer = resolution::load({"consumer.mt", R"(
module bootstrapOnly {}
import core.Value;
import core.Cursor;
type Local {
    value: i32
    init(value: i32) { self.value = value }
}
extend Local implements core.Value { fn get(): i32 { self.value } }
const MARKER: core.Marker = core.mark();
const ADDRESS6: core.Address6 = core.address6();
const ADDRESS_ALIAS: core.network.Address = core.network.Address.ALIAS;
const ADDRESS_FUNCTION: core.Address = core.address();
const RESULT: i32 = core.answer();
fn main(): i32 {
    let record = core.record();
    if core.network.Address.ORIGIN.bits != 2130706433u32 { return 1 }
    if core.Address6.LOCALHOST.octets[15] != 1u8 { return 1 }
    let pair = core.duplicate(RESULT);
    let value = pair.0;
    let borrowed = core.preserve(read value);
    var cursor = core.borrow(read value);
    match cursor.next() { present(_) => {}, none => {} }
    var mapped = core.mapper(fn(): i32 { 3 });
    match mapped.next() { present(_) => {}, none => {} }
    let first = core.Choice<i32>(3);
    let second = core.Choice<core.Owned>(4);
    if first.value != 3 || second.value != 5 { return 1 }
    core.add() + core.identity(*borrowed) + core.apply(1) + core.dispatch() +
        core.constIdentity(1) + record.get() + Local(1).get()
}
)"},
                                   provider, diagnostics, library);
  expect(consumer.has_value(),
         "different consumer mounts body-free declarations");
  expect(reads == 0, "source-free mounting never reads dependency sources");
  expect(headerReads == 1, "a genuine native reference loads its header once");
  if (!consumer) {
    errors(diagnostics);
    return 1;
  }
  std::map<std::pair<SymbolKind, std::string>, std::uint32_t> destinations;
  decode.symbol = [&](SymbolKind kind,
                      std::string_view name) -> std::optional<std::uint32_t> {
    auto found = destinations.find({kind, std::string(name)});
    return found == destinations.end() ? std::nullopt
                                       : std::optional(found->second);
  };
  auto types = std::make_shared<TypeStore>();
  (void)types->declareParameter("consumer-pollution", false);
  std::vector<Type> importedRoots;
  decode.type = [&](std::uint32_t index) -> std::optional<Type> {
    if (index >= importedRoots.size())
      return std::nullopt;
    return importedRoots[index];
  };
  std::shared_ptr<const ImportedDeclarations> imported;
  const auto consumerFunctionCount = consumer->functions.size();
  auto consumerPackages = library.compiledSourcePackages;
  consumerPackages.emplace(consumer->functions.back().span.source, "consumer");
  std::size_t observations = 0, imports = 0;
  auto importer =
      [&](const Module &module, const resolution::Resolution &namespaces,
          Diagnostics &) -> std::optional<pipeline::ImportedProgram> {
    ++imports;
    for (const auto &[key, name] : symbols) {
      auto index = key.second;
      if (key.first == SymbolKind::Package) {
        auto package = namespaces.packageIndex("library");
        if (!package)
          return std::nullopt;
        index = *package;
      } else if (key.first == SymbolKind::Function &&
                 index >= sourceFunctionCount)
        index += static_cast<std::uint32_t>(module.functions.size() -
                                            sourceFunctionCount);
      destinations.emplace(std::pair{key.first, name}, index);
    }
    metadata::TypeGraphSymbols importedSymbols;
    importedSymbols.resolve = decode.symbol;
    auto importedTypes =
        metadata::importTypeGraph(*types, graph.bytes, importedSymbols);
    if (!importedTypes)
      std::cerr << importedTypes.error << '\n';
    expect(bool(importedTypes),
           "logical types remap into a polluted type store");
    if (!importedTypes)
      return std::nullopt;
    importedRoots = std::move(importedTypes.roots);
    auto transientBytes = declarations.contracts;
    auto transientRoots = importedRoots;
    auto transientReferences = decode;
    transientReferences.type =
        [&](std::uint32_t reference) -> std::optional<Type> {
      return reference < transientRoots.size()
                 ? std::optional{transientRoots[reference]}
                 : std::nullopt;
    };
    auto retainedReferences =
        std::make_shared<metadata::DecodeReferences>(decode);
    retainedReferences->type =
        [roots =
             importedRoots](std::uint32_t reference) -> std::optional<Type> {
      return reference < roots.size() ? std::optional{roots[reference]}
                                      : std::nullopt;
    };
    std::optional<Module> indexedProgram;
    std::shared_ptr<const ImportedDeclarations> indexedDeclarations;
    resolution::Library indexedLibrary;
    if (!imported) {
      auto indexedBytes = std::make_shared<const std::vector<std::uint8_t>>(
          declarations.header);
      auto indexedHeader = decodeLibraryHeader(
          *indexedBytes, decode, indexedBytes, metadata::ValidationMode::OnUse);
      expect(
          indexedHeader &&
              indexedHeader.module->functions.admittedSize() == 0 &&
              indexedHeader.module->products.admittedSize() == 0 &&
              indexedHeader.module->implementations.admittedSize() == 0,
          "archive lookup mounts declaration address ranges without headers");
      expect(indexedHeader && indexedHeader.index->hasExternalLibraries() &&
                 indexedHeader.module->functions.admittedSize() == 0,
             "unused native link attributes preserve external-library cache "
             "policy without admitting declarations");
      if (!indexedHeader)
        return std::nullopt;
      auto contractsBytes = std::make_shared<const std::vector<std::uint8_t>>(
          declarations.contracts);
      indexedLibrary.compiledSourcePackages = library.compiledSourcePackages;
      indexedLibrary.compiledSourceModules = library.compiledSourceModules;
      indexedLibrary.compiled.push_back(
          {"core", [indexedHeader]() {
             return copyLibraryHeader(indexedHeader).module;
           }});
      Diagnostics indexedDiagnostics;
      auto indexedModule = resolution::load(
          {"indexed.mt", "const RESULT: i32 = core.answer();\n"
                         "fn main(): i32 { let invoke = fn(): i32 { RESULT }; "
                         "invoke() }\n"},
          [](const std::string &) { return std::optional<Source>{}; },
          indexedDiagnostics, indexedLibrary);
      expect(bool(indexedModule),
             "indexed declarations mount through module loading");
      if (!indexedModule)
        return std::nullopt;
      auto indexedNames =
          resolution::resolve(*indexedModule, indexedDiagnostics,
                              indexedLibrary.compiledSourcePackages);
      auto indexedContracts = importLibraryDeclarations(
          *contractsBytes, types, *retainedReferences, &*indexedModule,
          contractsBytes, retainedReferences, metadata::ValidationMode::OnUse,
          {}, {}, indexedHeader.index);
      expect(bool(indexedContracts),
             "indexed contracts admit complete implementation catalogs");
      if (!indexedContracts) {
        std::cerr << indexedContracts.error << '\n';
        return std::nullopt;
      }
      indexedBytes.reset();
      contractsBytes.reset();
      indexedProgram = *indexedModule;
      indexedDeclarations = indexedContracts.declarations;
      auto indexedChecked =
          check(std::move(*indexedModule), indexedDiagnostics, indexedNames,
                true, {}, nullptr, indexedContracts.declarations);
      if (!indexedDiagnostics.empty())
        errors(indexedDiagnostics);
      expect(indexedChecked && indexedChecked->statics().back().initializer &&
                 indexedChecked->statics()
                         .back()
                         .initializer->scalar.magnitude[0] == 10,
             "indexed lookup retains transitive defaults, private helpers and "
             "trait dispatch");
      auto dormant = expectedImplementations[1].find("core::Dormant");
      expect(indexedChecked && dormant != expectedImplementations[1].end() &&
                 !dormant->second.empty() &&
                 std::all_of(dormant->second.begin(), dormant->second.end(),
                             [&](std::size_t index) {
                               return !indexedChecked->interfaceDatabase()
                                           .implementations.isMaterialized(
                                               index);
                             }),
             "checking local contracts and regions leaves unused imported "
             "implementation bodies deferred");
      const auto admitted = indexedHeader.module->functions.admittedSize();
      expect(admitted == 5 &&
                 indexedHeader.module->implementations.admittedSize() == 0,
             "requested names do not admit unused declarations or "
             "implementation syntax");
      auto dormantId = indexedHeader.index->function("core::archivedUnused511");
      expect(dormantId &&
                 indexedHeader.module->functions.admittedSize() == admitted,
             "stable declaration ID lookup does not materialize its header");
      if (dormantId)
        expect(
            indexedHeader.module->functions.header(*dormantId).name ==
                    "archivedUnused511" &&
                indexedHeader.module->functions.admittedSize() == admitted + 1,
            "stable declaration IDs materialize exactly the requested header");
      std::cout << "indexed admission: " << admitted << '/'
                << sourceFunctionCount << " native functions\n";
      Diagnostics conflictDiagnostics;
      auto conflictModule = resolution::load(
          {"indexed-conflict.mt",
           "import core.answer;\n"
           "fn answer(): i32 { 0 }\nfn main(): i32 { 0 }\n"},
          [](const std::string &) { return std::optional<Source>{}; },
          conflictDiagnostics, indexedLibrary);
      if (conflictModule)
        resolution::resolve(*conflictModule, conflictDiagnostics,
                            indexedLibrary.compiledSourcePackages);
      expect(!conflictDiagnostics.empty(),
             "indexed imports preserve conflicts with local explicit bindings");
      Diagnostics constructorDiagnostics;
      auto constructorModule = resolution::load(
          {"indexed-constructors.mt",
           "fn main(): i32 {\n"
           "let first = core.Choice<i32>(3);\n"
           "let second = core.Choice<core.Owned>(4);\n"
           "first.value + second.value\n}\n"},
          [](const std::string &) { return std::optional<Source>{}; },
          constructorDiagnostics, indexedLibrary);
      auto constructorNames =
          constructorModule
              ? resolution::resolve(*constructorModule, constructorDiagnostics,
                                    indexedLibrary.compiledSourcePackages)
              : nullptr;
      auto constructorChecked =
          constructorModule
              ? check(std::move(*constructorModule), constructorDiagnostics,
                      constructorNames, true, {}, nullptr,
                      indexedContracts.declarations)
              : std::nullopt;
      if (!constructorDiagnostics.empty())
        errors(constructorDiagnostics);
      expect(bool(constructorChecked),
             "indexed constructor catalogs retain constrained alternatives");
      bool dormantConstructor = false;
      for (const auto &group : indexedContracts.declarations->constructorGroups)
        for (std::size_t i = 0; i < group->headers.size(); ++i)
          if (types->product(group->headers[i].origin).name ==
              "core::DormantConstructor")
            dormantConstructor = !group->applicability.isMaterialized(i);
      expect(dormantConstructor,
             "indexed constructor selection leaves unrelated applicability "
             "deferred");
      auto invalidDirectory = declarations.header;
      const std::string dormantKey = "f:core::archivedUnused511";
      auto dormantEntry =
          std::search(invalidDirectory.begin(), invalidDirectory.end(),
                      dormantKey.begin(), dormantKey.end());
      expect(dormantEntry != invalidDirectory.end(),
             "fixture has an archive-backed unused name lookup");
      if (dormantEntry != invalidDirectory.end()) {
        auto payload = dormantEntry + dormantKey.size();
        expect(invalidDirectory.end() - payload >= 2,
               "unused lookup retains its stable declaration ID");
        if (invalidDirectory.end() - payload >= 2) {
          for (auto id : {0u, 16383u}) {
            payload[0] = static_cast<std::uint8_t>((id & 0x7f) | 0x80);
            payload[1] = static_cast<std::uint8_t>(id >> 7);
            auto storage = std::make_shared<const std::vector<std::uint8_t>>(
                invalidDirectory);
            expect(!decodeLibraryHeader(*storage, decode, storage,
                                        metadata::ValidationMode::OnDemand),
                   "mounting rejects unknown and mismatched unused declaration "
                   "lookup IDs");
            auto queried = decodeLibraryHeader(*storage, decode, storage,
                                               metadata::ValidationMode::OnUse);
            expect(bool(queried),
                   "unused declaration payloads remain unqueried");
            bool rejected = false;
            try {
              if (queried)
                (void)queried.index->function("core::archivedUnused511");
            } catch (const metadata::InvalidMetadata &) {
              rejected = true;
            }
            expect(rejected,
                   "queried declaration IDs validate before publication");
          }
        }
      }
    }
    auto storage =
        std::make_shared<const std::vector<std::uint8_t>>(transientBytes);
    auto contracts = importLibraryDeclarations(
        *storage, types, *retainedReferences, &module, storage,
        retainedReferences, metadata::ValidationMode::OnDemand);
    if (!contracts)
      std::cerr << contracts.error << '\n';
    expect(bool(contracts),
           "checked contracts decode after symbol/type remapping");
    if (!contracts)
      return std::nullopt;
    bool deferredConstructors = false;
    for (const auto &group : contracts.declarations->constructorGroups)
      for (std::size_t i = 0; i < group->headers.size(); ++i) {
        deferredConstructors = true;
        expect(!group->applicability.isMaterialized(i),
               "constructor admission retains checked applicability on demand");
      }
    expect(deferredConstructors, "fixture exports checked constructor groups");
    for (const auto *database : {&contracts.declarations->checkingDatabase,
                                 &contracts.declarations->database}) {
      bool deferred = true;
      for (std::size_t i = 0; i < database->definitions.size(); ++i)
        deferred &= !database->definitions.isMaterialized(i);
      for (std::size_t i = 0; i < database->implementations.size(); ++i)
        deferred &= !database->implementations.isMaterialized(i);
      for (std::size_t i = 0; i < database->projections.size(); ++i)
        deferred &= !database->projections.isMaterialized(i);
      for (const auto &[key, index] :
           database->unpinImplementations.entries()) {
        (void)key;
        deferred &= !database->unpinImplementations.isMaterialized(index);
      }
      for (const auto &[key, index] :
           database->structuralDeclarations.entries()) {
        (void)key;
        deferred &= !database->structuralDeclarations.isMaterialized(index);
      }
      expect(deferred,
             "validated interface admission retains archive-backed details");
      bool deferredSelection = true;
      for (std::size_t i = 0; i < database->importedImplementations->size();
           ++i)
        deferredSelection &=
            !database->importedImplementations->isMaterialized(i);
      for (std::size_t i = 0; i < database->implementationsByDeclaration.size();
           ++i)
        deferredSelection &=
            !database->implementationsByDeclaration.isMaterialized(i);
      expect(deferredSelection,
             "mounting implementation selection builds no header or candidate "
             "inventories");
    }
    std::size_t phase = 0;
    for (const auto *database : {&contracts.declarations->checkingDatabase,
                                 &contracts.declarations->database}) {
      for (std::uint32_t owner = 0; owner < database->definitions.size();
           ++owner) {
        auto name = std::string(database->definitionName(owner));
        if (name != "core::ConstValue")
          continue;
        const auto &expected = expectedImplementations[phase].at(name);
        expect(database->implementationsFor(*types, owner) == expected &&
                   !database->implementations.isMaterialized(expected.back()),
               "producer candidate groups preserve all alternatives without "
               "demanding their details");
      }
      ++phase;
    }
    {
      const auto &database = contracts.declarations->database;
      for (std::uint32_t owner = 0; owner < database.definitions.size();
           ++owner) {
        if (database.definitionName(owner) != "core::ConstValue")
          continue;
        const auto &expected =
            expectedImplementations.back().at("core::ConstValue");
        const auto cold = expected.back();
        auto first = database, second = database;
        expect(!first.importedImplementations->isMaterialized(cold),
               "shared implementation header is cold before concurrent demand");
        const interfaces::Database::ImplementationHeader *left = nullptr,
                                                         *right = nullptr;
        std::barrier start(2);
        std::thread firstDemand([&] {
          start.arrive_and_wait();
          left = &(*first.importedImplementations)[cold];
        });
        std::thread secondDemand([&] {
          start.arrive_and_wait();
          right = &(*second.importedImplementations)[cold];
        });
        firstDemand.join();
        secondDemand.join();
        const auto &actual = database.implementations[cold];
        expect(left == right && left->interfaceType == actual.interfaceType &&
                   left->span == actual.span &&
                   left->declaration == actual.declaration &&
                   left->fallback == actual.fallback && left->inherent.empty(),
               "concurrent snapshots publish the same complete implementation "
               "header");
        const auto appended = first.implementations.size();
        first.implementations.push_back(actual);
        auto extended = expected;
        extended.push_back(appended);
        expect(first.implementationsFor(*types, owner) == extended &&
                   second.implementationsFor(*types, owner) == expected &&
                   database.implementationsFor(*types, owner) == expected,
               "source additions isolate consumer candidate overlays after "
               "concurrent shared header demand");
      }
    }
    if (!imported) {
      auto corrupt = module;
      auto owner = std::find_if(
          corrupt.implementations.begin(), corrupt.implementations.end(),
          [](const auto &item) {
            return std::any_of(item.associated.begin(), item.associated.end(),
                               [](const auto &item) { return item.constant; });
          });
      expect(owner != corrupt.implementations.end(),
             "fixture has a mounted associated constant");
      auto &associated = corrupt.implementations
                             .edit(static_cast<std::size_t>(
                                 owner - corrupt.implementations.begin()))
                             .associated;
      auto constant =
          std::find_if(associated.begin(), associated.end(),
                       [](const auto &item) { return item.constant; });
      constant->constant = false;
      expect(!importLibraryDeclarations(transientBytes, types,
                                        transientReferences, &corrupt),
             "admission rejects a constant contract bound to a nonconstant");
    }
    imported = std::move(contracts.declarations);
    auto bodies = ir::decodeProgram(programBytes.bytes, decode);
    if (!bodies)
      std::cerr << bodies.error << '\n';
    expect(bool(bodies), "symbolic dependency bodies decode");
    if (!bodies)
      return std::nullopt;
    auto bindings = std::make_shared<lowering::ImportedBodies>();
    bindings->statics = std::move(bodies.program.statics);
    for (std::size_t i = 0; i < sourceFunctionCount; ++i)
      bindings->functions.emplace(i,
                                  std::move(bodies.program.functions.edit(i)));
    for (std::size_t i = 0; i < defaultOwners.size(); ++i)
      bindings->defaults.emplace(
          defaultOwners[i],
          std::move(bodies.program.functions.edit(sourceFunctionCount + i)));
    for (std::size_t i = sourceFunctionCount + defaultOwners.size();
         i < bodies.program.functions.size(); ++i)
      bindings->support.push_back(std::move(bodies.program.functions.edit(i)));
    for (auto [closure, function] : bodies.closureFunctions) {
      if (bindings->closureFunctions.size() <= closure)
        bindings->closureFunctions.resize(std::size_t(closure) + 1, -1);
      bindings->closureFunctions[closure] = function;
    }
    auto metadata = std::move(bodies.program);
    metadata.functions.clear();
    metadata.statics.clear();
    metadata.closureFunctions.clear();
    if (indexedProgram) {
      const auto functions = indexedProgram->functions;
      const auto admitted = functions.admittedSize();
      Diagnostics indexedDiagnostics;
      pipeline::PackageOwners owners(library.compiledSourcePackages.begin(),
                                     library.compiledSourcePackages.end());
      auto indexedImporter =
          [&](const Module &, const resolution::Resolution &,
              Diagnostics &) -> std::optional<pipeline::ImportedProgram> {
        return pipeline::ImportedProgram{
            indexedDeclarations, bindings, metadata, {}};
      };
      auto indexedPrepared = pipeline::prepare(
          std::move(*indexedProgram), indexedDiagnostics, true, {}, {}, owners,
          nullptr, library.compiledSourcePackages, indexedImporter);
      if (!indexedDiagnostics.empty())
        errors(indexedDiagnostics);
      expect(indexedPrepared && functions.admittedSize() == admitted,
             "production lowering preserves sparse admission through closure "
             "default discovery and package ownership");
      pipeline::FunctionQueries queries;
      std::string querySource =
          "copy type Item { value: i32 }\n"
          "alias Word = Item;\n"
          "fn seed(): i32 { 3 }\n"
          "fn sample(): i32 { let item: Word = Item(seed()); item.value }\n"
          "fn main(): i32 { core.answer(sample()) }\n";
      for (unsigned revision = 0; revision < 3; ++revision) {
        if (revision == 2)
          querySource.replace(querySource.find("{ 3 }"), 5, "{ 4 }");
        auto prepareQuery = [&](pipeline::FunctionQueries *cache,
                                Diagnostics &diagnostics) {
          auto tree = resolution::load({"indexed-query.mt", querySource},
                                       provider, diagnostics, indexedLibrary);
          return tree ? pipeline::prepare(std::move(*tree), diagnostics, true,
                                          {}, {}, owners, nullptr,
                                          library.compiledSourcePackages,
                                          indexedImporter, cache)
                      : std::optional<pipeline::PreparedProgram>{};
        };
        Diagnostics queryDiagnostics, freshDiagnostics;
        auto before = queries.hits();
        auto reused = prepareQuery(&queries, queryDiagnostics);
        auto fresh = prepareQuery(nullptr, freshDiagnostics);
        if (!queryDiagnostics.empty())
          errors(queryDiagnostics);
        if (!freshDiagnostics.empty())
          errors(freshDiagnostics);
        expect(reused && fresh &&
                   queries.hits() - before == (revision == 0   ? 0u
                                               : revision == 1 ? 3u
                                                               : 2u),
               "native-backed source queries replay local products and aliases "
               "without invalidating independent functions");
        if (!reused || !fresh)
          break;
        auto reusedProgram = pipeline::compile(*reused, queryDiagnostics);
        auto freshProgram = pipeline::compile(*fresh, freshDiagnostics);
        expect(reusedProgram && freshProgram,
               "native-backed source query replay preserves executable "
               "admission");
        if (reusedProgram && freshProgram) {
          std::ostringstream reusedIR, freshIR;
          ir::print(reusedProgram->program(), reusedIR);
          ir::print(freshProgram->program(), freshIR);
          expect(reusedIR.str() == freshIR.str(),
                 "native-backed source query replay matches fresh executable "
                 "IR after a semantic edit");
        }
      }
      expect(functions.admittedSize() == admitted,
             "native-backed source query replay does not admit unused headers");
    }
    return pipeline::ImportedProgram{
        imported, std::move(bindings), std::move(metadata), {}};
  };
  auto prepared = pipeline::prepare(
      std::move(*consumer), diagnostics, true, {},
      [&](const CheckedModule &module) {
        ++observations;
        const auto &database = module.interfaceDatabase();
        bool dormant = false;
        for (std::size_t i = 0; i < database.definitions.size(); ++i)
          if (database.definitionName(i) == "core::Dormant") {
            const auto &candidates = database.implementationsFor(
                *module.typeStore(), static_cast<std::uint32_t>(i));
            dormant =
                !database.definitions.isMaterialized(i) &&
                candidates.size() == 1 &&
                !database.implementations.isMaterialized(candidates.front());
          }
        expect(dormant, "checking and coherence do not materialize unrelated "
                        "interface implementations");
        bool dormantConstructor = false;
        for (const auto &group : imported->constructorGroups)
          for (std::size_t i = 0; i < group->headers.size(); ++i)
            if (module.typeStore()->product(group->headers[i].origin).name ==
                "core::DormantConstructor")
              dormantConstructor = !group->applicability.isMaterialized(i);
        expect(dormantConstructor,
               "unused imported constructors reuse overlap proofs without "
               "materializing applicability");
        bool structuralDeferred = !database.structuralDeclarations.empty();
        for (const auto &[key, index] :
             database.structuralDeclarations.entries()) {
          (void)key;
          structuralDeferred &=
              !database.structuralDeclarations.isMaterialized(index);
        }
        expect(structuralDeferred,
               "region decoration preserves unused imported property records");
        expect(module.statics().back().initializer &&
                   module.statics().back().initializer->scalar.magnitude[0] ==
                       10,
               "imported const/default/private helper/static execute checked "
               "data");
        for (std::size_t offset : {2u, 3u}) {
          const auto &address =
              module.statics()[module.statics().size() - offset];
          expect(
              address.initializer &&
                  address.initializer->kind ==
                      StaticConstant::Kind::Aggregate &&
                  address.initializer->type == address.type &&
                  address.initializer->fields.size() == 1 &&
                  address.initializer->fields[0].scalar.magnitude[0] ==
                      2130706433u,
              "imported and reexported nominal constants retain typed values");
        }
        const auto &v6 =
            module.statics()[module.statics().size() - 4].initializer;
        expect(
            v6 && v6->kind == StaticConstant::Kind::Aggregate &&
                v6->fields.size() == 1 && v6->fields[0].fields.size() == 16 &&
                v6->fields[0].fields[15].scalar.magnitude[0] == 1,
            "imported const functions retain nested array constant payloads");
        for (std::size_t i = 0; i < sourceFunctionCount; ++i)
          expect(module.imported(i) && !module.syntax().functions[i].body.get(),
                 "observer sees no parsed dependency bodies");

        auto inventory = declarationInventory(module);
        for (const auto &[index, contract] : imported->functions)
          for (Type parameter : contract->contract().generics.parameters)
            expect(std::any_of(inventory.types.begin(), inventory.types.end(),
                               [&](const auto &identity) {
                                 return identity.type == parameter;
                               }),
                   "transitive imported generic appears in the inventory");
        std::vector<Type> roundtripTypes;
        std::map<Type, std::uint32_t> roundtripTypeIndices;
        std::map<std::string, SourceId> roundtripSources;
        std::map<std::pair<SymbolKind, std::string>, std::uint32_t>
            roundtripSymbols;
        metadata::EncodeReferences roundtripEncode;
        roundtripEncode.type = [&](Type type) -> std::optional<std::uint32_t> {
          auto [found, inserted] = roundtripTypeIndices.emplace(
              type, static_cast<std::uint32_t>(roundtripTypes.size()));
          if (inserted)
            roundtripTypes.push_back(type);
          return found->second;
        };
        roundtripEncode.source =
            [&](Span span) -> std::optional<metadata::SourceReference> {
          auto revision = std::to_string(span.source);
          roundtripSources.emplace(revision, span.source);
          return metadata::SourceReference{revision, std::uint32_t(span.begin),
                                           std::uint32_t(span.end)};
        };
        roundtripEncode.symbol =
            [&](SymbolKind kind,
                std::uint32_t index) -> std::optional<std::string> {
          auto name = std::to_string(index);
          roundtripSymbols.emplace(std::pair{kind, name}, index);
          return name;
        };
        auto transitive = exportLibraryDeclarations(module, roundtripEncode);
        if (!transitive)
          std::cerr << transitive.error << '\n';
        expect(bool(transitive), "consumer exports transitive contracts");
        if (transitive) {
          metadata::DecodeReferences roundtripDecode;
          roundtripDecode.type =
              [&](std::uint32_t index) -> std::optional<Type> {
            if (index >= roundtripTypes.size())
              return std::nullopt;
            return roundtripTypes[index];
          };
          roundtripDecode.source = [&](const metadata::SourceReference &source)
              -> std::optional<Span> {
            auto found = roundtripSources.find(source.revision);
            if (found == roundtripSources.end())
              return std::nullopt;
            return Span{source.begin, source.end, found->second};
          };
          roundtripDecode.symbol =
              [&](SymbolKind kind,
                  std::string_view name) -> std::optional<std::uint32_t> {
            auto found = roundtripSymbols.find({kind, std::string(name)});
            if (found == roundtripSymbols.end())
              return std::nullopt;
            return found->second;
          };
          auto restored = importLibraryDeclarations(
              transitive.contracts,
              std::make_shared<TypeStore>(*module.typeStore()),
              roundtripDecode);
          if (!restored)
            std::cerr << restored.error << '\n';
          expect(bool(restored), "transitive contracts import");
          if (restored) {
            expect(restored.declarations->functions.size() ==
                       consumerFunctionCount,
                   "transitive contracts include imported and local functions");
            for (const auto &[index, original] : imported->functions) {
              auto found = restored.declarations->functions.find(index);
              expect(found != restored.declarations->functions.end(),
                     "transitive contract retains imported function");
              if (found == restored.declarations->functions.end())
                continue;
              const auto &actual = *found->second;
              expect(actual.contract().generics.parameters ==
                             original->contract().generics.parameters &&
                         actual.contract().facts.locals.size() ==
                             original->contract().facts.locals.size() &&
                         bool(actual.body) == bool(original->body) &&
                         actual.defaults.size() == original->defaults.size(),
                     "transitive contract retains generics and checked bodies");
              for (std::size_t p = 0; p < actual.defaults.size(); ++p)
                expect(bool(actual.defaults[p]) == bool(original->defaults[p]),
                       "transitive contract retains checked defaults");
            }
          }
        }
      },
      {}, nullptr, consumerPackages, importer);
  if (!prepared)
    errors(diagnostics);
  expect(bool(prepared) && observations == 1 && imports == 1,
         "pipeline prepares a different consumer using checked imports");
  if (!prepared)
    return 1;
  expect(prepared->program().functions[consumerFunctionCount].blocks.size() > 0,
         "runtime default helper contains executable verified symbolic IR");
  expect(prepared->program().opaqueAdapters.size() == adapterCount,
         "imported adapter metadata is reused by pipeline preparation");
  if (prepared)
    expect(bool(pipeline::compile(std::move(*prepared), diagnostics)),
           "prepared imports compile after the checked syntax is destroyed");
  expect(reads == 0, "pipeline import never requests dependency source bytes");
  if (!diagnostics.empty())
    errors(diagnostics);
  auto truncated = declarations.contracts;
  truncated.pop_back();
  expect(!importLibraryDeclarations(truncated, types, decode),
         "truncated contract payload is rejected");
  auto invalidUnused = declarations.contracts;
  auto unusedMethod = std::find_end(invalidUnused.begin(), invalidUnused.end(),
                                    dormantMethod.begin(), dormantMethod.end());
  expect(!dormantMethod.empty() && unusedMethod != invalidUnused.end(),
         "fixture retains its unused implementation method reference");
  if (!dormantMethod.empty() && unusedMethod != invalidUnused.end()) {
    *unusedMethod = '!';
    auto invalid = importLibraryDeclarations(invalidUnused, types, decode);
    expect(
        !invalid && invalid.error.find("unknown logical declaration symbol") !=
                        std::string::npos,
        "admission rejects malformed references in unused interface details");
    auto storage =
        std::make_shared<const std::vector<std::uint8_t>>(invalidUnused);
    auto references =
        std::make_shared<const metadata::DecodeReferences>(decode);
    auto deferred = importLibraryDeclarations(*storage, types, *references,
                                              nullptr, storage, references,
                                              metadata::ValidationMode::OnUse);
    expect(bool(deferred), "unused implementation bodies remain unqueried");
    auto dormant = std::find_if(
        expectedImplementations[1].begin(), expectedImplementations[1].end(),
        [](const auto &entry) { return entry.first.ends_with("Dormant"); });
    expect(dormant != expectedImplementations[1].end() &&
               dormant->second.size() == 1,
           "fixture has one dormant implementation");
    if (deferred && dormant != expectedImplementations[1].end())
      for (unsigned retry = 0; retry != 2; ++retry) {
        bool rejected = false;
        try {
          auto index = dormant->second.front();
          (void)(*deferred.declarations->database
                      .importedImplementations)[index];
          expect(
              !deferred.declarations->database.implementations.isMaterialized(
                  index),
              "indexing an implementation does not decode its body");
          (void)deferred.declarations->database.implementations[index];
        } catch (const metadata::InvalidMetadata &) {
          rejected = true;
        }
        expect(rejected,
               "selected implementation bodies validate before publication");
      }
  }
  auto wrongSelection = declarations.contracts;
  auto candidate = std::search(wrongSelection.begin(), wrongSelection.end(),
                               selectionRecord.begin(), selectionRecord.end());
  expect(!selectionRecord.empty() && candidate != wrongSelection.end(),
         "fixture retains its producer-built implementation candidate group");
  if (!selectionRecord.empty() && candidate != wrongSelection.end()) {
    auto word = candidate + selectionRecord.size() - 4;
    for (unsigned byte = 0; byte < 4; ++byte)
      word[byte] = static_cast<std::uint8_t>(foreignCandidate >> (byte * 8));
    auto invalid = importLibraryDeclarations(wrongSelection, types, decode);
    expect(!invalid && invalid.error.find("implementation candidate") !=
                           std::string::npos,
           "unused candidate indexes cannot substitute a valid implementation "
           "from another interface");
  }
  auto overflowing = declarations.contracts;
  overflowing.front() |= 0x80;
  overflowing.insert(overflowing.begin() + 1, 8, 0x80);
  overflowing.insert(overflowing.begin() + 9, 0x02);
  expect(!importLibraryDeclarations(overflowing, types, decode),
         "overflowing LEB128 tag length is rejected");
  auto invalidReferences = decode;
  invalidReferences.type = {};
  expect(!importLibraryDeclarations(declarations.contracts, types,
                                    invalidReferences),
         "missing type references fail explicitly");
  invalidReferences = decode;
  invalidReferences.source = {};
  expect(!decodeLibraryHeader(declarations.header, invalidReferences),
         "header mounting rejects missing source revision references");
  {
    auto shifted = headerReferences;
    shifted.sourceRange =
        [&](std::string_view revision) -> std::optional<Span> {
      if (revision == "library-revision")
        return Span{9, source.size() + 9, 42};
      if (revision == "reexport-revision")
        return Span{9, reexportSource.text.size() + 9, 43};
      return std::nullopt;
    };
    auto header = decodeLibraryHeader(declarations.header, shifted);
    expect(bool(header), "revision ranges accept relocated source text");
    if (header) {
      auto original = retainedHeader->module->functions.header(0).span;
      expect(header.module->functions.header(0).span ==
                 Span{original.begin + 9, original.end + 9, original.source},
             "revision ranges relocate declaration source positions");
    }
    for (auto range : {std::optional<Span>{}, std::optional(Span{0, 0, 42}),
                       std::optional(Span{2, 1, 42})}) {
      shifted.sourceRange = [range](std::string_view) { return range; };
      expect(!decodeLibraryHeader(declarations.header, shifted),
             "revision ranges reject unknown and out-of-bounds sources");
    }
  }
  auto unknownSource = declarations.header;
  const std::string_view revision = "library-revision";
  auto revisionBytes = std::search(unknownSource.begin(), unknownSource.end(),
                                   revision.begin(), revision.end());
  const std::string_view reexportRevision = "reexport-revision";
  auto reexportBytes =
      std::search(unknownSource.begin(), unknownSource.end(),
                  reexportRevision.begin(), reexportRevision.end());
  expect(revisionBytes >= unknownSource.begin() + 2 &&
             revisionBytes != unknownSource.end() &&
             reexportBytes != unknownSource.end(),
         "fixture contains an indexed source revision");
  if (revisionBytes >= unknownSource.begin() + 2 &&
      revisionBytes != unknownSource.end() &&
      reexportBytes != unknownSource.end()) {
    auto sourceIndex = std::max(revisionBytes + revision.size(),
                                reexportBytes + reexportRevision.size());
    while (sourceIndex != unknownSource.end() && (*sourceIndex++ & 0x80)) {
    }
    expect(sourceIndex != unknownSource.end(),
           "fixture contains an indexed source reference");
    if (sourceIndex != unknownSource.end())
      *sourceIndex = 2;
    std::size_t sourceReads = 0;
    invalidReferences = decode;
    invalidReferences.source =
        [&](const metadata::SourceReference &) -> std::optional<Span> {
      ++sourceReads;
      return std::nullopt;
    };
    auto rejected = decodeLibraryHeader(unknownSource, invalidReferences);
    expect(!rejected &&
               rejected.error == "invalid declaration source reference" &&
               sourceReads == 0,
           "unknown source indexes fail before calling external resolvers");
  }
  auto trailing = declarations.header;
  trailing.push_back(0);
  expect(!decodeLibraryHeader(trailing, decode),
         "header mounting rejects trailing bytes");
  auto oversized = declarations.contracts;
  const auto inventoryOffset =
      1 + std::string_view("mettle.checked-contracts.23").size();
  oversized[inventoryOffset] = 0xff;
  oversized.insert(oversized.begin() + inventoryOffset + 1, 8, 0xff);
  oversized.insert(oversized.begin() + inventoryOffset + 9, 0x01);
  expect(!importLibraryDeclarations(oversized, types, decode),
         "oversized function inventories fail before allocation");
  for (std::size_t i = 0; i < 48; ++i) {
    auto mutated = declarations.contracts;
    mutated[i * mutated.size() / 48] ^= 0xff;
    (void)importLibraryDeclarations(mutated, types, decode);
  }
  Diagnostics rejectedDiagnostics;
  auto rejectedSource =
      resolution::load({"rejected.mt", "fn main(): i32 { core.hidden(2) }\n"},
                       provider, rejectedDiagnostics, library);
  if (!rejectedSource) {
    errors(rejectedDiagnostics);
    expect(false, "rejected consumer loads its declarations");
    return 1;
  }
  auto rejectedNames = resolution::resolve(*rejectedSource, rejectedDiagnostics,
                                           library.compiledSourcePackages);
  auto rejected = check(std::move(*rejectedSource), rejectedDiagnostics,
                        rejectedNames, true, {}, nullptr, imported);
  expect(!rejected && !rejectedDiagnostics.empty(),
         "new consumer cannot bypass imported private visibility");
  {
    Diagnostics conflicts;
    auto module =
        resolution::load({"constructor-conflict.mt",
                          "extend core.Choice<i32> {\n"
                          "    init(value: i32) { self.value = value }\n"
                          "}\nfn main(): i32 { 0 }\n"},
                         provider, conflicts, library);
    expect(bool(module), "local constructor extension mounts its dependency");
    if (module) {
      auto names = resolution::resolve(*module, conflicts,
                                       library.compiledSourcePackages);
      auto checked = check(std::move(*module), conflicts, names, true, {},
                           nullptr, imported);
      expect(!checked &&
                 std::any_of(conflicts.items.begin(), conflicts.items.end(),
                             [](const auto &item) {
                               return item.message.find(
                                          "overlapping constructor argument "
                                          "shapes") != std::string::npos;
                             }),
             "local constructors are checked against imported applicability");
    }
  }
  auto constantValue = [&](const std::string &text, std::uint64_t expected) {
    Diagnostics diagnostics;
    auto module = resolution::load({"unsupported-constant.mt", text}, provider,
                                   diagnostics, library);
    if (!module)
      return false;
    auto names = resolution::resolve(*module, diagnostics,
                                     library.compiledSourcePackages);
    auto checked = check(std::move(*module), diagnostics, names, true, {},
                         nullptr, imported);
    if (!checked || !diagnostics.empty())
      return false;
    const auto &value = checked->statics().back().initializer;
    return value && value->kind == StaticConstant::Kind::Scalar &&
           value->scalar == integerLiteral(expected);
  };
  expect(
      constantValue(
          "static VALUE: i32 = core.constIdentity(7);\nfn main(): i32 { 0 }\n",
          7),
      "imported generic const functions retain the evaluated value");
  expect(
      constantValue("static VALUE: i32 = { let value = core.record(); 11 };\n"
                    "fn main(): i32 { 0 }\n",
                    11),
      "imported const records execute with their concrete shapes");
  Diagnostics nonConstDiagnostics;
  auto nonConstSource = resolution::load(
      {"non-const-interface.mt",
       "static VALUE: i32 = core.runtimeValue();\nfn main(): i32 { 0 }\n"},
      provider, nonConstDiagnostics, library);
  expect(bool(nonConstSource), "non-const interface consumer loads");
  if (nonConstSource) {
    auto names = resolution::resolve(*nonConstSource, nonConstDiagnostics,
                                     library.compiledSourcePackages);
    auto rejected = check(std::move(*nonConstSource), nonConstDiagnostics,
                          names, true, {}, nullptr, imported);
    const bool rejectsNonConst =
        !rejected &&
        std::any_of(nonConstDiagnostics.items.begin(),
                    nonConstDiagnostics.items.end(), [](const auto &item) {
                      return item.phase == "constant" &&
                             item.message.find("non-const function") !=
                                 std::string::npos;
                    });
    if (!rejectsNonConst)
      errors(nonConstDiagnostics);
    expect(rejectsNonConst,
           "imported interface dispatch rejects non-const implementations");
  }
  {
    Source source{"overlap.mt", "interface Marker {}\n"
                                "extend i32 implements Marker {}\n"
                                "extend i32 implements Marker {}\n"
                                "fn main(): i32 { 0 }\n"};
    Diagnostics diagnostics;
    auto tree = parse(source, diagnostics);
    auto checked = check(std::move(tree), diagnostics);
    auto first = source.text.find("extend");
    auto second = source.text.find("extend", first + 1);
    bool bothSpans = diagnostics.items.size() == 1;
    if (bothSpans) {
      const auto &error = diagnostics.items.front();
      bothSpans =
          error.phase == "type" &&
          error.message ==
              "overlapping implementations cannot be selected by order" &&
          error.related.size() == 1;
      if (bothSpans) {
        const auto &note = error.related.front();
        bothSpans =
            note.kind == "note" && note.span &&
            note.message == "conflicting implementation is declared here" &&
            ((error.span.begin == first && note.span->begin == second) ||
             (error.span.begin == second && note.span->begin == first));
      }
    }
    expect(!checked && bothSpans,
           "genuine overlap identifies both implementation spans");
  }
  std::cout << failures << " failures\n";
  return failures ? 1 : 0;
}
