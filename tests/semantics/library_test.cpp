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
#include <iostream>
#include <map>

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
} // namespace

int main() {
  using namespace mettle;
  using metadata::SymbolKind;
  const std::string source = R"(
pub module core {
    const BASE: i32 = 4;
    const fn hidden(x: i32): i32 { x + BASE }
    pub const fn answer(x: i32 = hidden(2)): i32 { hidden(x) }
    pub fn identity<T>(take value: T): T { value }
    pub const fn constIdentity<T: Copy>(value: T): T { value }
    pub fn add(x: i32 = hidden(3)): i32 { x + 1 }
    pub interface Family {
        type Item<T: Copy>: Copy;
        const FLAG: bool;
    }
    pub type Number {}
    pub const fn record(): Number { Number() }
    pub copy enum Marker { First, Last }
    pub const fn mark(): Marker { Marker.Last }
    pub interface Value { fn get(): i32; }
    extend Number implements Value { fn get(): i32 { 5 } }
    pub interface Cursor { type Item; mut fn next(): Self.Item?; }
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
  Diagnostics diagnostics;
  auto checked =
      check(parse({"library.mt", source}, diagnostics), diagnostics, false);
  if (!checked) {
    errors(diagnostics);
    expect(false, "source library checks");
    return 1;
  }
  auto symbolic = lowering::lower(*checked, diagnostics);
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
  std::vector<std::pair<std::size_t, std::size_t>> defaultOwners;
  for (std::size_t i = 0; i < sourceFunctionCount; ++i)
    for (std::size_t p = 0;
         p < checked->syntax().functions[i].parameters.size(); ++p)
      if (checked->hasDefault(i, p))
        defaultOwners.emplace_back(i, p);
  checked.reset();
  symbolic = {};

  metadata::DecodeReferences decode;
  decode.source =
      [](const metadata::SourceReference &reference) -> std::optional<Span> {
    if (reference.revision != "library-revision")
      return std::nullopt;
    return Span{reference.begin, reference.end, 42};
  };
  resolution::Library library;
  std::size_t headerReads = 0;
  auto makeHeader = [&]() -> std::optional<Module> {
    ++headerReads;
    library.compiledSourcePackages.emplace(42, "library");
    library.compiledSourceModules.emplace(42, std::vector<std::string>{"core"});
    auto header = decodeLibraryHeader(declarations.header, decode);
    if (!header)
      std::cerr << header.error << '\n';
    return std::move(header.module);
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
type Local { value: i32 }
extend Local implements core.Value { fn get(): i32 { self.value } }
const MARKER: core.Marker = core.mark();
const RESULT: i32 = core.answer();
fn main(): i32 {
    let record = core.record();
    let pair = core.duplicate(RESULT);
    let value = pair.0;
    let borrowed = core.preserve(read value);
    var cursor = core.borrow(read value);
    match cursor.next() { present(_) => {}, none => {} }
    var mapped = core.mapper(fn(): i32 { 3 });
    match mapped.next() { present(_) => {}, none => {} }
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
    auto contracts =
        importLibraryDeclarations(declarations.contracts, types, decode);
    if (!contracts)
      std::cerr << contracts.error << '\n';
    expect(bool(contracts),
           "checked contracts decode after symbol/type remapping");
    if (!contracts)
      return std::nullopt;
    imported = std::move(contracts.declarations);
    auto bodies = ir::decodeProgram(programBytes.bytes, decode);
    if (!bodies)
      std::cerr << bodies.error << '\n';
    expect(bool(bodies), "symbolic dependency bodies decode");
    if (!bodies)
      return std::nullopt;
    auto bindings = std::make_shared<lowering::ImportedBodies>();
    for (std::size_t i = 0; i < sourceFunctionCount; ++i)
      bindings->functions.emplace(i, std::move(bodies.program.functions[i]));
    for (std::size_t i = 0; i < defaultOwners.size(); ++i)
      bindings->defaults.emplace(
          defaultOwners[i],
          std::move(bodies.program.functions[sourceFunctionCount + i]));
    for (std::size_t i = sourceFunctionCount + defaultOwners.size();
         i < bodies.program.functions.size(); ++i)
      bindings->support.push_back(std::move(bodies.program.functions[i]));
    for (auto [closure, function] : bodies.closureFunctions) {
      if (bindings->closureFunctions.size() <= closure)
        bindings->closureFunctions.resize(std::size_t(closure) + 1, -1);
      bindings->closureFunctions[closure] = function;
    }
    auto metadata = std::move(bodies.program);
    metadata.functions.clear();
    metadata.statics.clear();
    metadata.closureFunctions.clear();
    return pipeline::ImportedProgram{imported, std::move(bindings),
                                     std::move(metadata)};
  };
  auto prepared = pipeline::prepare(
      std::move(*consumer), diagnostics, true, {},
      [&](const CheckedModule &module) {
        ++observations;
        expect(module.statics().back().initializer &&
                   module.statics().back().initializer->scalar.magnitude[0] ==
                       10,
               "imported const/default/private helper/static execute checked "
               "data");
        for (std::size_t i = 0; i < sourceFunctionCount; ++i)
          expect(module.imported(i) && !module.syntax().functions[i].body.get(),
                 "observer sees no parsed dependency bodies");
      },
      {}, nullptr, consumerPackages, nullptr, nullptr, importer);
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
  auto invalidReferences = decode;
  invalidReferences.type = {};
  expect(!importLibraryDeclarations(declarations.contracts, types,
                                    invalidReferences),
         "missing type references fail explicitly");
  invalidReferences = decode;
  invalidReferences.source = {};
  expect(!decodeLibraryHeader(declarations.header, invalidReferences),
         "header mounting rejects missing source revision references");
  auto trailing = declarations.header;
  trailing.push_back(0);
  expect(!decodeLibraryHeader(trailing, decode),
         "header mounting rejects trailing bytes");
  auto oversized = declarations.contracts;
  const auto inventoryOffset =
      sizeof(std::uint64_t) +
      std::string_view("mettle.checked-contracts.2").size();
  std::fill_n(oversized.begin() + inventoryOffset, sizeof(std::uint64_t), 0xff);
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
  std::cout << failures << " failures\n";
  return failures ? 1 : 0;
}
