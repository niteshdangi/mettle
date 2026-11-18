#include "expansion/macros.h"
#include "pipeline/compile.h"
#include "resolution/load.h"
#include "resolution/resolve.h"
#include "semantics/check.h"
#include "semantics/interfaces.h"
#include "semantics/library.h"
#include "semantics/region_solver.h"
#include "source/positions.h"
#include "syntax/parser.h"
#include <algorithm>
#include <atomic>
#include <charconv>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <thread>
#include <tuple>
#include <utility>

namespace {
void require(bool condition, const char *message) {
  if (!condition)
    throw std::runtime_error(message);
}

void inMemorySources() {
  mettle::Source positions{"positions.mt",
                           "a\r\n\xc3\xa9\nz\r\xf0\x9f\x98\x80"};
  mettle::SourcePositions indexed(positions.text);
  for (std::size_t offset = 0; offset <= positions.text.size() + 1; ++offset) {
    auto expected = mettle::sourcePosition(positions, offset);
    auto actual = indexed.position(offset);
    require(actual.line == expected.line && actual.column == expected.column,
            "indexed source positions changed UTF-8 or newline semantics");
  }
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "module math;\nimport math.{answer as result};\n"
                         "fn main() { result() - 42 }\n"},
      {"memory/math.mt", "pub fn answer() { 42 }\n"}};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::resolution::load(sources, diagnostics);
  auto resolved =
      tree ? mettle::resolution::resolve(*tree, diagnostics) : nullptr;
  if (!resolved)
    diagnostics.print(sources.front(), std::cerr);
  require(resolved && diagnostics.empty(), "in-memory module loading failed");
  require(tree->functions[0].span.source != tree->functions[1].span.source,
          "external source spans were flattened into the root source");
  mettle::Diagnostics compilationDiagnostics;
  require(
      mettle::pipeline::compile(sources, compilationDiagnostics).has_value(),
      "in-memory multi-source pipeline failed");
}

void demandLoadedFunctionContracts() {
  using namespace mettle;
  const std::string source =
      "pub const fn answer(value: i32 = 7): i32 { value + 1 }\n"
      "pub const fn unused(): i32 { 987654321 }\n";
  Diagnostics diagnostics;
  auto checked =
      check(parse({"demand.mt", source}, diagnostics), diagnostics, false);
  require(bool(checked), "demand-loaded contract fixture did not check");
  auto types = std::const_pointer_cast<TypeStore>(checked->typeStore());
  metadata::EncodeReferences encode;
  encode.type = [](Type type) { return std::optional(type.index()); };
  encode.source = [&](Span span) {
    return std::optional(metadata::SourceReference{
        span.begin == source.find("987654321") ? "missing" : "fixture",
        static_cast<std::uint32_t>(span.begin),
        static_cast<std::uint32_t>(span.end)});
  };
  encode.symbol = [](metadata::SymbolKind, std::uint32_t index) {
    return std::optional(std::to_string(index));
  };
  auto exported = exportLibraryDeclarations(*checked, encode);
  require(bool(exported), "demand-loaded contract fixture did not export");
  checked.reset();
  auto bytes = std::make_shared<const std::vector<std::uint8_t>>(
      std::move(exported.contracts));
  auto references = std::make_shared<metadata::DecodeReferences>();
  references->type = [types](std::uint32_t index) -> std::optional<Type> {
    if (index >= builtinTypeCount + types->storedTypeCount())
      return std::nullopt;
    return types->typeAt(index);
  };
  references->source =
      [](const metadata::SourceReference &reference) -> std::optional<Span> {
    if (reference.revision != "fixture")
      return std::nullopt;
    return Span{reference.begin, reference.end, 42};
  };
  references->symbol =
      [](metadata::SymbolKind,
         std::string_view name) -> std::optional<std::uint32_t> {
    std::uint32_t index = 0;
    auto parsed =
        std::from_chars(name.data(), name.data() + name.size(), index);
    if (parsed.ec != std::errc{} || parsed.ptr != name.data() + name.size())
      return std::nullopt;
    return index;
  };
  require(!importLibraryDeclarations(*bytes, types, *references),
          "eager import accepted an unresolved expression source");
  auto mounted = decodeLibraryHeader(exported.header, *references);
  require(bool(mounted), "demand-loaded declaration header did not decode");
  auto imported = importLibraryDeclarations(*bytes, types, *references,
                                            &*mounted.module, bytes, references,
                                            metadata::ValidationMode::OnDemand);
  require(bool(imported), imported.error.c_str());
  for (const auto &[index, function] : imported.declarations->functions) {
    (void)index;
    require(!function.isMaterialized(),
            "mounting a declaration materialized its unused function contract");
  }
  auto resolved = resolution::resolve(*mounted.module, diagnostics);
  auto consumer =
      check(std::move(*mounted.module), diagnostics, std::move(resolved), false,
            {}, nullptr, imported.declarations);
  require(bool(consumer),
          "demand-loaded declarations failed consumer semantic admission");
  for (const auto &[index, function] : imported.declarations->functions) {
    (void)index;
    require(!function.isMaterialized(),
            "semantic admission expanded an unused function contract");
  }
  references.reset();
  bytes.reset();
  const auto &answer = *imported.declarations->functions.at(0);
  require(answer.resultType() == Type::I32 && answer.defaults.at(0),
          "demand-loaded function lost its signature or default");
  answer.defaults[0]->materialize();
  answer.body->materialize();
  require(answer.defaults[0]->syntax.get() && answer.body->syntax.get() &&
              answer.contract().facts.result == Type::I32,
          "demand-loaded expressions did not survive resolver destruction");
  require(!imported.declarations->functions.at(1).isMaterialized(),
          "using one function materialized an unrelated function contract");
  bool rejected = false;
  try {
    imported.declarations->functions.at(1)->body->materialize();
  } catch (const metadata::InvalidMetadata &) {
    rejected = true;
  }
  require(rejected,
          "demanded malformed function was published without validation");
}

void demandLoadedDeclarationHeaders() {
  using namespace mettle;
  std::vector<Source> sources{{"headers.mt", R"(
macro packet { () => { pub type Packet<T> { pub item: T? } }; }
packet!();
pub alias Word = i32;
pub interface Marker {}
pub interface Borrowed { fn value(): read i32 from self; }
pub type Scalar { pub item: i32; pub data: [i32; 2 + 3] }
pub type ClosureHolder<F> { pub callback: F }
extend Scalar implements Borrowed {
  fn value(): read i32 from self { read self.item }
}
extend<F: take fn(mut i32): Unit> ClosureHolder<F> implements Marker {}
pub const DEFAULT: i32 = 7;
pub const fn answer(value: i32 = 7): i32 { value }
extern "C" fn native(value: i32): i32 { value }
@link("archive_dependency")
extern "C" fn linked_native(): i32;
)"}};
  Diagnostics diagnostics;
  auto tree = resolution::load(sources, diagnostics);
  auto symbols = tree ? resolution::resolve(*tree, diagnostics) : nullptr;
  auto checked =
      symbols ? check(std::move(*tree), diagnostics, std::move(symbols), false)
              : std::nullopt;
  require(bool(checked), "deferred declaration fixture did not check");
  auto types = std::const_pointer_cast<TypeStore>(checked->typeStore());
  metadata::EncodeReferences encode;
  encode.type = [](Type type) { return std::optional(type.index()); };
  encode.source = [](Span span) {
    return std::optional(metadata::SourceReference{
        std::to_string(span.source), static_cast<std::uint32_t>(span.begin),
        static_cast<std::uint32_t>(span.end)});
  };
  encode.symbol = [](metadata::SymbolKind, std::uint32_t index) {
    return std::optional(std::to_string(index));
  };
  auto exported = exportLibraryDeclarations(*checked, encode);
  require(bool(exported), "deferred declaration fixture did not export");
  auto references = std::make_shared<metadata::DecodeReferences>();
  references->type = [types](std::uint32_t index) -> std::optional<Type> {
    return index < builtinTypeCount + types->storedTypeCount()
               ? std::optional(types->typeAt(index))
               : std::nullopt;
  };
  references->source =
      [](const metadata::SourceReference &source) -> std::optional<Span> {
    SourceId id = 0;
    auto parsed =
        std::from_chars(source.revision.data(),
                        source.revision.data() + source.revision.size(), id);
    if (parsed.ec != std::errc{} ||
        parsed.ptr != source.revision.data() + source.revision.size())
      return std::nullopt;
    return Span{source.begin, source.end, id};
  };
  references->symbol =
      [](metadata::SymbolKind,
         std::string_view name) -> std::optional<std::uint32_t> {
    std::uint32_t index = 0;
    auto parsed =
        std::from_chars(name.data(), name.data() + name.size(), index);
    return parsed.ec == std::errc{} && parsed.ptr == name.data() + name.size()
               ? std::optional(index)
               : std::nullopt;
  };
  LibraryHeaderImport header;
  std::weak_ptr<int> resolverLifetime;
  {
    auto lifetime = std::make_shared<int>(0);
    resolverLifetime = lifetime;
    auto transient = *references;
    transient.source = [resolve = references->source,
                        lifetime](const auto &source) {
      (void)*lifetime;
      return resolve(source);
    };
    header = decodeLibraryHeader(exported.header, transient);
  }
  require(bool(header) && resolverLifetime.expired(),
          "deferred header retained its caller's resolver");
  exported.header.clear();
  exported.header.shrink_to_fit();
  auto retained = copyLibraryHeader(header);
  header.module.reset();
  auto &module = *retained.module;
  auto productIndex = [&](std::string_view name) {
    auto headers = module.products.headers();
    auto found =
        std::find_if(headers.begin(), headers.end(),
                     [&](const auto &item) { return item.name == name; });
    require(found != headers.end(), "deferred product fixture is missing");
    return static_cast<std::size_t>(found - headers.begin());
  };
  const auto packet = productIndex("Packet");
  const auto scalar = productIndex("Scalar");
  auto unexpanded = [&](const auto &items) {
    for (std::size_t i = 0; i < items.size(); ++i)
      require(!items.isMaterialized(i),
              "metadata-only admission reconstructed complete syntax");
  };
  unexpanded(module.products);
  unexpanded(module.aliases);
  unexpanded(module.interfaces);
  unexpanded(module.implementations);
  unexpanded(module.statics);
  auto functionHeaders = module.functions.headers();
  auto linked = std::find_if(
      functionHeaders.begin(), functionHeaders.end(),
      [](const auto &function) { return function.name == "linked_native"; });
  require(
      linked != functionHeaders.end() &&
          !module.functions.isMaterialized(linked - functionHeaders.begin()) &&
          linked->item.attributes.size() == 1 &&
          linked->item.attributes[0].name == "link" &&
          linked->item.attributes[0].arguments.size() == 1 &&
          linked->item.attributes[0].arguments[0].text ==
              "\"archive_dependency\"",
      "compact declaration lookup lost deferred external linkage");
  require(module.products.header(packet).fields[0].name == "item" &&
              module.products.header(packet).fields[0].visibility.publicItem &&
              module.aliases.header(0).target.name == "i32" &&
              module.implementations.header(0).target.name == "Scalar" &&
              module.implementations.header(0).interface.name == "Borrowed" &&
              !module.implementations.header(0).methodFunctions.empty(),
          "compact declaration headers lost resolution metadata");
  auto resolved = resolution::resolve(module, diagnostics);
  require(bool(resolved), "compact declaration headers did not resolve");
  unexpanded(module.products);
  unexpanded(module.aliases);
  unexpanded(module.interfaces);
  unexpanded(module.implementations);
  auto layout = declarationPayloadLayout(exported.contracts);
  require(bool(layout) && layout.payloads.size() == module.functions.size() &&
              !layout.payloads.empty() && layout.payloads[0].size,
          "checked function payload framing lost a declaration");
  auto damaged = exported.contracts;
  damaged[layout.payloads[0].offset] ^= 0x7f;
  auto reversed = std::make_shared<metadata::DecodeReferences>(*references);
  reversed->symbol = [resolve = references->symbol,
                      count = layout.payloads.size()](metadata::SymbolKind kind,
                                                      std::string_view name) {
    auto index = resolve(kind, name);
    if (kind == metadata::SymbolKind::Function && index && *index < count)
      *index = static_cast<std::uint32_t>(count - *index - 1);
    return index;
  };
  unsigned verified = 0;
  auto rejectedPayload = importLibraryDeclarations(
      damaged, types, *reversed, nullptr, {}, reversed,
      metadata::ValidationMode::OnDemand, {},
      [&](std::size_t ordinal, std::span<const std::uint8_t> payload) {
        ++verified;
        require(
            ordinal == 0 && payload.size() == layout.payloads[ordinal].size &&
                std::equal(payload.begin(), payload.end(),
                           damaged.begin() + layout.payloads[ordinal].offset),
            "payload verification used a consumer index or wrong bytes");
        return false;
      });
  require(bool(rejectedPayload) && verified == 0,
          "admission read an undemanded checked function payload");
  bool rejected = false;
  try {
    rejectedPayload.declarations->functions
        .at(static_cast<std::uint32_t>(layout.payloads.size() - 1))
        ->contract();
  } catch (const metadata::InvalidMetadata &error) {
    rejected = std::string_view(error.what()).find("integrity") !=
               std::string_view::npos;
  }
  require(rejected && verified == 1,
          "demanded checked payload bypassed integrity verification");
  verified = 0;
  auto eagerRejection = importLibraryDeclarations(
      damaged, types, *references, nullptr, {}, references,
      metadata::ValidationMode::Eager, {},
      [&](std::size_t ordinal, std::span<const std::uint8_t>) {
        ++verified;
        return ordinal != 0;
      });
  require(!eagerRejection && verified == 1 &&
              eagerRejection.error.find("integrity") != std::string::npos,
          "eager checked payload bypassed integrity verification");
  auto imported = importLibraryDeclarations(
      exported.contracts, types, *references, &module, {}, references,
      metadata::ValidationMode::OnDemand);
  require(bool(imported), imported.error.c_str());
  unexpanded(module.products);
  unexpanded(module.aliases);
  unexpanded(module.interfaces);
  unexpanded(module.implementations);
  require(imported.declarations->index->annotations.empty(),
          "admission populated annotations for undemanded syntax");
  auto consumerSyntax = module;
  auto consumerResolution = resolution::resolve(consumerSyntax, diagnostics);
  auto consumer = check(std::move(consumerSyntax), diagnostics,
                        std::move(consumerResolution), false, {}, nullptr,
                        imported.declarations);
  require(bool(consumer),
          "metadata-only imported declarations failed consumer checking");
  unexpanded(consumer->syntax().products);
  unexpanded(consumer->syntax().aliases);
  unexpanded(consumer->syntax().interfaces);
  unexpanded(consumer->syntax().implementations);
  unexpanded(consumer->syntax().statics);
  unexpanded(consumer->syntax().functions);
  auto copy = module;
  std::atomic<unsigned> loads = 0;
  module.products.onMaterialize(packet, [&](auto) { ++loads; });
  const Module::Product *first = nullptr, *second = nullptr;
  std::thread a([&] { first = &module.products[packet]; });
  std::thread b([&] { second = &copy.products[packet]; });
  a.join();
  b.join();
  require(first == second && loads == 1 && first->fields[0].annotation.nested &&
              first->fields[0].annotation.nested->name == "T" &&
              first->genericParameters[0].context &&
              first->fields[0].annotation.nested->context &&
              first->genericParameters[0].context->identity ==
                  first->fields[0].annotation.nested->context->identity,
          "deferred syntax lost shared loading, nested types or hygiene");
  copy.products.edit(packet).fields[0].name = "changed";
  require(module.products[packet].fields[0].name == "item",
          "consumer syntax mutation changed another mounted archive");
  Declarations<Module::Product> mounted;
  mounted.push_back({});
  mounted.append(module.products);
  std::vector<std::size_t> notifications;
  mounted.onMaterializeAll([&](std::size_t index, auto declaration) {
    if (index) {
      require(declaration->name == mounted.header(index).name,
              "mounted syntax observer used an archive-local index");
      notifications.push_back(index);
    }
  });
  require(notifications == std::vector<std::size_t>{packet + 1},
          "batch syntax observer missed an already materialized declaration");
  (void)mounted[scalar + 1];
  require(notifications == std::vector<std::size_t>{packet + 1, scalar + 1} &&
              module.products.isMaterialized(scalar),
          "batch syntax observer lost shared deferred materialization");
  auto method = module.implementations.header(0).methodFunctions.at(0);
  auto rebased = module.functions;
  rebased.transformHeader(
      method, [](Function &function) { function.implementation += 5; });
  require(!rebased.isMaterialized(method) &&
              rebased.header(method).implementation == 5 &&
              rebased[method].implementation == 5 &&
              module.functions.header(method).implementation == 0,
          "header rebasing forced syntax or missed its deferred record");
  const auto &alias = module.aliases[0];
  require(imported.declarations->index->annotations.contains(&alias.target),
          "demanded alias syntax did not receive its checked annotation");
  const auto &checking = imported.declarations->checkingDatabase;
  const auto &finalized = imported.declarations->database;
  const auto &expected = checked->declarations()->checkingDatabase;
  const auto &expectedFinalized = checked->interfaceDatabase();
  require(&checking.definitions[0] == &finalized.definitions[0] &&
              checking.definitions[1].methods[0].signature.result ==
                  expected.definitions[1].methods[0].signature.result &&
              finalized.definitions[1].methods[0].signature.result ==
                  expectedFinalized.definitions[1].methods[0].signature.result,
          "phase differences lost immutable sharing or region contracts");
  require(checking.callableContracts.empty() &&
              !finalized.callableContracts.empty() &&
              finalized.callableContracts.size() ==
                  expectedFinalized.callableContracts.size(),
          "finalized callable region contracts were merged into checking");
  for (const auto &[parameter, contract] : expectedFinalized.callableContracts)
    require(finalized.callableContracts.at(parameter) == contract,
            "finalized callable region contract did not survive admission");
  auto generic = std::find_if(
      imported.declarations->implementations.begin(),
      imported.declarations->implementations.end(),
      [](const auto &item) { return !item->generics.parameters.empty(); });
  require(generic != imported.declarations->implementations.end(),
          "generic environment fixture is missing");
  const DeclarationEnvironment *firstEnvironment = nullptr;
  const DeclarationEnvironment *secondEnvironment = nullptr;
  std::thread firstDemand(
      [&] { firstEnvironment = &(*generic)->environment(); });
  std::thread secondDemand(
      [&] { secondEnvironment = &(*generic)->environment(); });
  firstDemand.join();
  secondDemand.join();
  auto expectedEnvironment = checked->declarations()->findType(
      (*generic)->span, checked->declarations()->implementations);
  require(expectedEnvironment && firstEnvironment == secondEnvironment &&
              firstEnvironment->parameters ==
                  expectedEnvironment->generics.parameters &&
              !firstEnvironment->names.empty() &&
              firstEnvironment->names.size() ==
                  expectedEnvironment->generics.names.size() &&
              firstEnvironment->bounds.size() ==
                  expectedEnvironment->generics.bounds.size(),
          "demanded generic environment lost names, bounds or shared loading");
  auto changed = finalized;
  changed.definitions[0].name = "Changed";
  require(checking.definitions[0].name == "Marker" &&
              finalized.definitions[0].name == "Marker",
          "consumer database mutation changed a retained phase");
  auto &annotation = const_cast<Module &>(checked->syntax())
                         .products.edit(scalar)
                         .fields[1]
                         .annotation;
  auto form = annotation.form;
  annotation.form = static_cast<TypeForm>(unsigned(TypeForm::Owner) + 1);
  auto invalidSyntax = exportLibraryDeclarations(*checked, encode);
  annotation.form = form;
  auto deferredInvalid = decodeLibraryHeader(invalidSyntax.header, *references);
  require(bool(invalidSyntax) && bool(deferredInvalid) &&
              !deferredInvalid.module->products.isMaterialized(scalar),
          "compact queries traversed an unused syntax record");
  rejected = false;
  try {
    (void)deferredInvalid.module->products[scalar];
  } catch (const metadata::InvalidMetadata &) {
    rejected = true;
  }
  require(rejected, "demanded syntax bypassed enumeration validation");
  auto expression =
      checked->syntax().products[scalar].fields[1].annotation.countExpression;
  require(bool(expression), "type-expression corruption fixture is missing");
  auto originalSource = encode.source;
  encode.source = [originalSource, rejected = expression->span](Span span) {
    auto reference = originalSource(span);
    if (span.source == rejected.source && span.begin == rejected.begin &&
        span.end == rejected.end)
      reference->revision = "missing";
    return reference;
  };
  auto corrupted = exportLibraryDeclarations(*checked, encode);
  require(bool(corrupted) &&
              !decodeLibraryHeader(corrupted.header, *references),
          "discarded type syntax bypassed source-reference validation");
}

void residentFunctionQueries() {
  mettle::pipeline::FunctionQueries queries;
  auto print = [](const mettle::ir::Program &input, std::ostream &out) {
    auto program = input;
    for (std::size_t i = 0; i < program.functions.size(); ++i)
      if (program.functions[i].indirectContract)
        program.functions.edit(i).name = "<indirect-contract>";
    mettle::ir::print(program, out);
  };
  auto prepare = [&](const std::string &text, mettle::Diagnostics &diagnostics,
                     mettle::pipeline::FunctionQueries *cache) {
    auto tree = mettle::parse({"memory/query.mt", text}, diagnostics);
    return mettle::pipeline::prepare(std::move(tree), diagnostics, true, {}, {},
                                     {}, nullptr, {}, {}, cache);
  };
  auto query = [&](const std::string &text, std::size_t hits,
                   bool valid = true) {
    mettle::Diagnostics diagnostics, freshDiagnostics;
    auto before = queries.hits();
    auto result = prepare(text, diagnostics, &queries);
    auto fresh = prepare(text, freshDiagnostics, nullptr);
    if (bool(result) != valid || bool(fresh) != valid) {
      diagnostics.print({"memory/query.mt", text}, std::cerr);
      freshDiagnostics.print({"memory/query.mt", text}, std::cerr);
      throw std::runtime_error(
          "resident function query changed source acceptance:\n" + text);
    }
    if (queries.hits() - before != hits)
      throw std::runtime_error(
          "resident function query invalidated the wrong dependents: " +
          std::to_string(queries.hits() - before) + " instead of " +
          std::to_string(hits) + "\n" + text);
    std::size_t specialized = 0;
    if (valid) {
      std::ostringstream reused, uncached;
      print(result->program(), reused);
      print(fresh->program(), uncached);
      if (reused.str() != uncached.str())
        throw std::runtime_error(
            "resident function query changed prepared IR:\n" + text +
            "\nCached:\n" + reused.str() + "\nFresh:\n" + uncached.str());
      auto previousSpecializations = queries.specializationHits();
      auto executable = mettle::pipeline::compile(*result, diagnostics);
      auto freshExecutable =
          mettle::pipeline::compile(*fresh, freshDiagnostics);
      if (!executable || !freshExecutable) {
        diagnostics.print({"memory/query.mt", text}, std::cerr);
        freshDiagnostics.print({"memory/query.mt", text}, std::cerr);
        throw std::runtime_error(
            "resident function query failed executable admission");
      }
      reused.str({});
      uncached.str({});
      print(executable->program(), reused);
      print(freshExecutable->program(), uncached);
      require(reused.str() == uncached.str(),
              "resident specialization changed concrete IR");
      specialized = queries.specializationHits() - previousSpecializations;
    } else {
      require(!diagnostics.empty() && !freshDiagnostics.empty() &&
                  diagnostics.items.front().phase ==
                      freshDiagnostics.items.front().phase,
              "resident function query lost the fresh diagnostic phase");
    }
    return specialized;
  };
  const std::string source = "fn leaf() { 1i32 }\n"
                             "fn caller(): i32 { leaf() }\n"
                             "fn independent(): i32 { 9 }\n"
                             "fn main(): i32 { caller() + independent() }\n";
  query(source, 0);
  query(source, 4);
  auto changed = source;
  changed.replace(changed.find("1i32"), 4, "2i32");
  query(changed, 2);
  query(changed, 4);
  changed.replace(changed.find("2i32"), 4, "true");
  query(changed, 2, false);
  query(source, 2);
  query(source, 4);

  const std::string fixed = "fn leaf(): i32 { 1 }\n"
                            "fn caller(): i32 { leaf() }\n"
                            "fn main(): i32 { caller() }\n";
  query(fixed, 0);
  changed = fixed;
  changed.replace(changed.find("{ 1 }"), 5, "{ 2 }");
  require(query(changed, 2) == 2,
          "fixed call contracts invalidated callers or lost current binding");

  const std::string unreachable =
      "fn leaf() { 1i32 }\n"
      "fn unused(): i32 { return 0; let value: i32 = leaf(); value }\n"
      "fn main(): i32 { 0 }\n";
  query(unreachable, 0);
  changed = unreachable;
  changed.replace(changed.find("1i32"), 4, "true");
  query(changed, 1, false);

  const std::string generic = "fn identity<T>(take value: T): T { value }\n"
                              "fn main(): i32 { identity(7) }\n";
  query(generic, 0);
  require(query(generic, 2) > 0, "resident generic instances were not reused");
  changed = generic;
  changed.replace(changed.find("identity(7)"), 11, "identity(8)");
  require(query(changed, 1) > 0,
          "edited callers discarded unchanged generic specializations");

  const std::string structural =
      "fn identity<T>(take value: T): T { value }\n"
      "fn noise(): i32 { let unused = ([0;2], 0); 0 }\n"
      "fn main(): i32 { identity([7, 8])[0] }\n";
  query(structural, 0);
  changed = structural;
  changed.replace(changed.find("([0;2], 0)"), 10, "(0, 0, 0 )");
  changed.replace(changed.find("[7, 8]"), 6, "[8, 9]");
  require(query(changed, 1) > 0,
          "structural specialization was not remapped after type renumbering");
  changed.replace(changed.find("[8, 9]"), 6, "[8; 3]");
  require(query(changed, 2) == 1,
          "changed array arguments must reuse only the independent function");

  const std::string nominal =
      "copy type Item { value: i32 }\n"
      "type Box<T> { value: T }\n"
      "fn identity<T>(take value: T): T { value }\n"
      "fn noise(): i32 { let unused = ([0;2], 0); 0 }\n"
      "fn main(): i32 { identity(Box(Item(7))).value.value }\n";
  query(nominal, 0);
  changed = nominal;
  changed.replace(changed.find("([0;2], 0)"), 10, "(0, 0, 0 )");
  changed.replace(changed.find("Item(7)"), 7, "Item(8)");
  require(query(changed, 1) > 0,
          "nominal specialization was not remapped after type renumbering");
  changed.replace(changed.find("value: i32"), 10, "value: i64");
  changed.replace(changed.find(".value.value }"), 14, ".value.value as i32 }");
  query(changed, 0);

  const std::string reordered = "fn first(): i32 { 1 }\n"
                                "fn leaf(): i32 { 2 }\n"
                                "fn independent(): i32 { leaf() }\n"
                                "fn main(): i32 { first() + independent() }\n";
  query(reordered, 0);
  changed = reordered;
  changed.replace(changed.find("first() + independent()"), 23,
                  "independent() + first()");
  require(query(changed, 3) > 0,
          "reordered demand discarded unchanged specializations");

  const std::string indirect =
      "fn apply(callback: fn(i32): i32, value: i32): i32 { callback(value) }\n"
      "fn increment(value: i32): i32 { value + 1 }\n"
      "fn main(): i32 { apply(increment, 6) }\n";
  query(indirect, 0);
  auto reusedPointers = query(indirect, 3);
  require(reusedPointers == 3,
          ("function-pointer contracts prevented specialization reuse: " +
           std::to_string(reusedPointers))
              .c_str());
  changed = indirect;
  changed.replace(changed.find("value + 1"), 9, "value + 2");
  query(changed, 1);

  const std::string callable =
      "fn identity<T>(take value: T): T { value }\n"
      "fn increment(value: i32): i32 { value + 1 }\n"
      "fn noise(): i32 { let unused = ([0;2], 0); 0 }\n"
      "fn main(): i32 { let pointer: fn(i32): i32 = increment; "
      "let operation = identity(pointer); operation(7) }\n";
  query(callable, 0);
  changed = callable;
  changed.replace(changed.find("([0;2], 0)"), 10, "(0, 0, 0 )");
  changed.replace(changed.find("operation(7)"), 12, "operation(8)");
  require(query(changed, 2) == 2,
          "function-pointer specialization was not remapped after type "
          "renumbering");

  std::string quietNoise = "{ 0 }";
  quietNoise.insert(quietNoise.size() - 1, 100, ' ');
  std::string callingNoise = "{ let pointer: fn(bool): bool = flip; "
                             "if pointer(true) { 1 } else { 0 } }";
  callingNoise.insert(callingNoise.size() - 1,
                      quietNoise.size() - callingNoise.size(), ' ');
  const std::string contractOrder =
      "fn reserve(pointer: fn(bool): bool): bool { true }\n"
      "fn noise(): i32 " +
      quietNoise +
      "\n"
      "fn apply(pointer: fn(i32): i32, value: i32): i32 { pointer(value) }\n"
      "fn flip(value: bool): bool { !value }\n"
      "fn increment(value: i32): i32 { value + 1 }\n"
      "fn main(): i32 { apply(increment, 7) }\n";
  query(contractOrder, 0);
  changed = contractOrder;
  changed.replace(changed.find(quietNoise), quietNoise.size(), callingNoise);
  require(query(changed, 5) == 5,
          "reordered indirect contracts were not rebound to the current "
          "request");

  const std::string higherRanked =
      "fn apply<F: for<region r> fn(read i32 from r): read i32 from r>("
      "read operation: F, read value: i32): read i32 from value { "
      "operation(value) }\n"
      "fn identity<region r>(read value: i32 from r): read i32 from r "
      "{ read value }\n"
      "fn noise(): i32 { let unused = ([0;2], 0); 0 }\n"
      "fn main(): i32 { let pointer: for<region r> fn(read i32 from r): "
      "read i32 from r = identity; let value = 7; *apply(pointer, value) }\n";
  query(higherRanked, 0);
  require(query(higherRanked, 4) == 4,
          "higher-ranked callback specializations were not reused");
  changed = higherRanked;
  changed.replace(changed.find("([0;2], 0)"), 10, "(0, 0, 0 )");
  changed.replace(changed.find("value = 7"), 9, "value = 8");
  require(query(changed, 2) == 2,
          "higher-ranked callback binders were not remapped after type "
          "renumbering");

  const std::string borrowedCallback =
      "fn keep<T>(take value: T): T { value }\n"
      "fn identity<region r>(read value: i32 from r): read i32 from r "
      "{ read value }\n"
      "fn invoke<region r>(read value: i32 from r): i32 { "
      "let pointer: fn(read i32 from r): read i32 from r = identity; "
      "let operation = keep(pointer); *operation(value) }\n"
      "fn main(): i32 { let value = 7; invoke(value) }\n";
  query(borrowedCallback, 0);
  require(query(borrowedCallback, 4) == 4,
          "checked region-erased callback specializations were not reused");
  changed = borrowedCallback;
  changed.replace(changed.find("*operation(value)"), 17, "*operation(true )");
  query(changed, 2, false);

  const std::string initialized =
      "fn leaf(): i32 { var value: i32; var other: i32; value = 1; value }\n"
      "fn independent(): i32 { 9 }\n"
      "fn main(): i32 { leaf() + independent() }\n";
  query(initialized, 0);
  changed = initialized;
  changed.replace(changed.find("value = 1"), 9, "other = 1");
  query(changed, 2, false);
  query(initialized, 3);

  const std::string interfaces = "interface Marker {}\n"
                                 "extend i32 implements Marker {}\n"
                                 "fn leaf(): i32 { 1 }\n"
                                 "fn independent(): i32 { 7 }\n"
                                 "fn main(): i32 { leaf() + independent() }\n";
  query(interfaces, 0);
  query(interfaces, 3);
  changed = interfaces;
  changed.replace(changed.find("{ 1 }"), 5, "{ 2 }");
  query(changed, 2);

  const std::string closures =
      "fn noise(): i32 { let unused = (0, 0);            "
      "let call = fn(): i32 { 3 }; call() }\n"
      "fn independent(): i32 { 7 }\n"
      "fn main(): i32 { noise() + independent() }\n";
  query(closures, 0);
  query(closures, 1);
  changed = closures;
  const std::string oldClosure = "let unused = (0, 0);            ";
  std::string newClosure = "let unused = fn(): i32 { 0 };";
  newClosure.resize(oldClosure.size(), ' ');
  changed.replace(changed.find(oldClosure), oldClosure.size(), newClosure);
  query(changed, 1);

  const std::string statics =
      "static VALUE: i32 = 7\n"
      "fn cached_value(): i32 { VALUE }\n"
      "fn independent(): i32 { 3 }\n"
      "fn main(): i32 { cached_value() + independent() }\n";
  query(statics, 0);
  query(statics, 3);
  changed = statics;
  changed.replace(changed.find("= 7"), 3, "= 9");
  query(changed, 0);
  query(changed, 3);

  query("type Guard<T> { value: T; drop {} }\n"
        "fn accept(p: ptr<mut Guard<i32>>): i32 { 0 }\n"
        "fn main(): i32 { 0 }\n",
        0);

  mettle::pipeline::FunctionQueries edited;
  std::size_t retainedTypes = 0;
  for (unsigned iteration = 0; iteration < 8; ++iteration) {
    auto text = "fn independent(): i32 { 7 }\n"
                "fn leaf(): i32 { let values = [0; " +
                std::to_string(1000 + iteration) +
                "]; values[0] }\n"
                "fn main(): i32 { independent() + leaf() }\n";
    mettle::Diagnostics diagnostics;
    auto before = edited.hits();
    auto result = prepare(text, diagnostics, &edited);
    require(result.has_value(), "resident array edit failed preparation");
    require(edited.hits() - before == (iteration ? 2u : 0u),
            "array edits lost unchanged fixed-contract callers");
    auto count = result->program().types->storedTypes().size();
    if (iteration == 2)
      retainedTypes = count;
    else if (iteration > 2)
      require(count <= retainedTypes,
              "resident edits retained types from obsolete function bodies");
  }
}

void ordinaryImportsDoNotLoadMacroModules() {
  mettle::Diagnostics diagnostics;
  mettle::expansion::MacroModuleProvider provider =
      [](const auto &,
         const auto &) -> std::optional<mettle::expansion::MacroModuleSource> {
    throw std::runtime_error("ordinary imports triggered macro module loading");
  };
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt", "import std.io.Reader\nfn main() { 0 }\n"},
      diagnostics, [] { return mettle::SourceId{1}; }, nullptr, {}, provider);
  require(!expanded && diagnostics.empty(),
          "source without macro invocations was expanded");
}

const mettle::Node &singleValue(const mettle::Node *value) {
  require(value, "discovery fixture lost its result expression");
  while (value->kind == mettle::Kind::Block ||
         value->kind == mettle::Kind::Group) {
    require(value->children.size() == 1 && value->children[0].get(),
            "discovery fixture did not produce one result expression");
    value = value->children[0].get();
  }
  return *value;
}

const mettle::Node &mainValue(const mettle::Module &tree) {
  for (const auto &function : tree.functions)
    if (function.name == "main")
      return singleValue(function.body.get());
  throw std::runtime_error("discovery fixture lost main");
}

void unitLiteralKeepsSource() {
  mettle::Source source{"memory/nonroot.mt", "fn main(): Unit { () }\n", 7};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  const auto &unit = mainValue(tree);
  require(diagnostics.empty() && unit.kind == mettle::Kind::Unit &&
              unit.span.source == source.id &&
              source.text.substr(unit.span.begin,
                                 unit.span.end - unit.span.begin) == "()",
          "unit literal lost its non-root source identity");
}

void localMacroDoesNotDiscoverOrdinaryImports() {
  mettle::Diagnostics diagnostics;
  unsigned requests = 0;
  mettle::expansion::MacroModuleProvider provider =
      [&](const auto &,
          const auto &) -> std::optional<mettle::expansion::MacroModuleSource> {
    ++requests;
    throw std::runtime_error("local macro discovered an unrelated import");
  };
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt", "import unused.Value\n"
                         "macro never { () => { unused.trap!() }; }\n"
                         "macro answer { () => { 0 }; }\n"
                         "fn main() { answer!() }\n"},
      diagnostics, [] { return mettle::SourceId{100}; }, nullptr, {}, provider,
      nullptr, provider);
  require(expanded && diagnostics.empty() && requests == 0,
          "local macro did not expand without unrelated discovery");
  auto tree = mettle::parse(*expanded, diagnostics);
  require(diagnostics.empty(), "local macro produced invalid syntax");
  const auto &value = mainValue(tree);
  require(value.kind == mettle::Kind::Integer && value.text == "0",
          "local macro expanded the wrong definition");
}

void demandedMacroReexportSkipsValueImportCycle() {
  using Request =
      std::tuple<std::vector<std::string>, std::vector<std::string>, bool>;
  std::map<Request, unsigned> requests;
  auto provider = [&](bool imported) {
    return [&, imported](const auto &path, const auto &from)
               -> std::optional<mettle::expansion::MacroModuleSource> {
      require(++requests[{path, from, imported}] == 1,
              "macro reexport repeated a provider request");
      if (path == std::vector<std::string>{"relay"})
        return mettle::expansion::MacroModuleSource{
            {"memory/relay.mt", "pub import leaf.answer\nimport cycle.Unused\n",
             11},
            path,
            path};
      if (path == std::vector<std::string>{"leaf"})
        return mettle::expansion::MacroModuleSource{
            {"memory/leaf.mt",
             "pub macro answer { () => { 42 }; }\nimport relay.Unused\n", 12},
            path,
            path};
      throw std::runtime_error("macro discovery followed an unrelated import");
    };
  };
  mettle::Diagnostics diagnostics;
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt", "import relay.answer\nfn main() { answer!() }\n"},
      diagnostics, [] { return mettle::SourceId{100}; }, nullptr, {},
      provider(false), nullptr, provider(true));
  require(expanded && diagnostics.empty(),
          "demanded macro reexport did not expand");
  auto tree = mettle::parse(*expanded, diagnostics);
  require(diagnostics.empty(), "macro reexport produced invalid syntax");
  const auto &value = mainValue(tree);
  require(value.kind == mettle::Kind::Integer && value.text == "42",
          "macro reexport selected the wrong definition");
}

void selectedMacroImportCycleTerminatesWithoutRepeatedReads() {
  using Request =
      std::tuple<std::vector<std::string>, std::vector<std::string>, bool>;
  std::map<Request, unsigned> requests;
  bool readA = false, readB = false;
  auto provider = [&](bool imported) {
    return [&, imported](const auto &path, const auto &from)
               -> std::optional<mettle::expansion::MacroModuleSource> {
      require(++requests[{path, from, imported}] == 1,
              "cyclic macro import repeated a provider request");
      if (path == std::vector<std::string>{"a"}) {
        readA = true;
        return mettle::expansion::MacroModuleSource{
            {"memory/a.mt", "pub import b.answer\n", 11}, path, path};
      }
      if (path == std::vector<std::string>{"b"}) {
        readB = true;
        return mettle::expansion::MacroModuleSource{
            {"memory/b.mt", "pub import a.answer\n", 12}, path, path};
      }
      throw std::runtime_error("macro cycle discovered an unrelated module");
    };
  };
  mettle::Diagnostics diagnostics;
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt", "import a.answer\nfn main() { answer!() }\n"},
      diagnostics, [] { return mettle::SourceId{100}; }, nullptr, {},
      provider(false), nullptr, provider(true));
  require(!expanded && diagnostics.empty() && readA && readB,
          "unresolved macro cycle fabricated an expansion or diagnostic");
}

void missingQualifiedMacroDiscoveryIsMemoized() {
  using Request =
      std::tuple<std::vector<std::string>, std::vector<std::string>, bool>;
  std::map<Request, unsigned> requests;
  auto provider = [&](bool imported) {
    return [&, imported](const auto &path, const auto &from)
               -> std::optional<mettle::expansion::MacroModuleSource> {
      require(++requests[{path, from, imported}] == 1,
              "missing macro repeated an identical provider request");
      return std::nullopt;
    };
  };
  mettle::Diagnostics diagnostics;
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt",
       "fn main() { external.missing!() + external.missing!() }\n"},
      diagnostics, [] { return mettle::SourceId{100}; }, nullptr, {},
      provider(false), nullptr, provider(true));
  require(!expanded && diagnostics.empty() && !requests.empty(),
          "missing macro fabricated an expansion or diagnostic");
}

void macroDiscoveryDistinguishesProviderKinds() {
  using Request =
      std::tuple<std::vector<std::string>, std::vector<std::string>, bool>;
  std::map<Request, unsigned> requests;
  const std::vector<std::string> external{"host", "external"};
  auto provider = [&](bool imported) {
    return [&, imported](const auto &path, const auto &from)
               -> std::optional<mettle::expansion::MacroModuleSource> {
      require(++requests[{path, from, imported}] == 1,
              "provider-kind discovery repeated a request");
      if (path == external) {
        require(from == std::vector<std::string>{"user"},
                "provider-kind fixture changed the lookup scope");
        if (imported)
          return std::nullopt;
        return mettle::expansion::MacroModuleSource{
            {"memory/host/external/module.mt",
             "pub macro missing { () => { 42 }; }\n", 12},
            external,
            external};
      }
      if (path == std::vector<std::string>{"host", "probe"})
        return mettle::expansion::MacroModuleSource{
            {"memory/host/main.mt",
             "pub module probe { pub macro trigger { () => { 0 }; } }\n"
             "pub module external;\n",
             11},
            path,
            {"host"}};
      throw std::runtime_error(
          "provider-kind fixture discovered another module");
    };
  };
  mettle::Diagnostics diagnostics;
  auto expanded = mettle::expansion::expandMacros(
      {"memory/root.mt",
       "macro missing { () => { 0 }; }\n"
       "module user { import host.external.missing;\n"
       "fn main() { (missing!(), host.probe.trigger!(), missing!()) } }\n"},
      diagnostics, [] { return mettle::SourceId{100}; }, nullptr, {},
      provider(false), nullptr, provider(true));
  require(expanded && diagnostics.empty(),
          "provider-kind fixture did not expand");
  auto tree = mettle::parse(*expanded, diagnostics);
  require(diagnostics.empty(),
          "provider-kind expansion produced invalid syntax");
  const auto &result = mainValue(tree);
  require(result.kind == mettle::Kind::Tuple && result.children.size() == 3,
          "provider-kind fixture lost its result tuple");
  for (std::size_t i = 0; i < result.children.size(); ++i) {
    const auto &value = singleValue(result.children[i].get());
    require(value.kind == mettle::Kind::Integer &&
                value.text == (i == 2 ? "42" : "0"),
            "negative import cache poisoned later declared-module discovery");
  }
  require(requests[{external, {"user"}, true}] == 1 &&
              requests[{external, {"user"}, false}] == 1,
          "provider-kind fixture did not exercise import miss/module success");
}

void importedDirectoryModulesLoadModuleFile() {
  for (bool declared : {false, true}) {
    mettle::resolution::SourceProvider provider =
        [](const std::string &path) -> std::optional<mettle::Source> {
      if (path == "memory/child/main.mt")
        return mettle::Source{path, "pub macro value { () => { 7 }; }\n"};
      if (path == "memory/child/module.mt")
        return mettle::Source{path, "pub macro value { () => { 42 }; }\n"};
      return std::nullopt;
    };
    mettle::Diagnostics diagnostics;
    auto tree = mettle::resolution::load(
        {"memory/root.mt", std::string(declared ? "module child;\n" : "") +
                               "import child.value;\nfn main() { value!() }\n"},
        provider, diagnostics);
    require(tree && diagnostics.empty(), "macro file discovery failed");
    const auto &value = mainValue(*tree);
    require(value.kind == mettle::Kind::Integer && value.text == "42",
            "imported directory module did not load module.mt");
    auto symbols = mettle::resolution::resolve(*tree, diagnostics);
    require(symbols && diagnostics.empty(),
            "macro discovery left an unresolved module/import");
  }
}

void unknownOwnershipCannotGrantLocality() {
  auto reject = [](const char *text, const char *message) {
    mettle::Source source{"memory/unknown-owner.mt", text};
    mettle::Diagnostics diagnostics;
    auto tree = mettle::parse(source, diagnostics);
    mettle::resolution::SourcePackages ownership{{source.id, ""}};
    auto symbols = mettle::resolution::resolve(tree, diagnostics, ownership);
    require(symbols && diagnostics.empty() && !tree.functions.empty() &&
                !symbols->packageOf(tree.functions.front().span),
            "unknown-owner fixture did not resolve with unknown provenance");
    require(!mettle::check(std::move(tree), diagnostics, symbols),
            "unknown package ownership established locality");
    require(std::any_of(diagnostics.items.begin(), diagnostics.items.end(),
                        [&](const auto &item) {
                          return item.phase == "type" &&
                                 item.severity == "error" &&
                                 item.message.find(message) !=
                                     std::string::npos;
                        }),
            "unknown ownership failed for an unrelated reason");
  };
  reject("interface Foreign {}\nextend i32 implements Foreign {}\n"
         "fn main(): i32 { 0 }\n",
         "orphan interface implementation has no local owner");
  reject("type Nominal {}\nunsafe extend Nominal implements Unpin {}\n"
         "fn main(): i32 { 0 }\n",
         "Unpin implementation must belong to the type's package");
  reject("type Nominal {}\nextend Nominal not Transferable;\n"
         "fn main(): i32 { 0 }\n",
         "Transferable declaration must belong to the type's package");

  mettle::Source source{
      "memory/known-owner.mt",
      "interface Local {}\ntype Owned {}\n"
      "extend i32 implements Local {}\n"
      "unsafe extend Owned implements Unpin {}\n"
      "extend Owned not Transferable;\nfn main(): i32 { 0 }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  mettle::resolution::SourcePackages ownership{{source.id, "fixture-root"}};
  auto symbols = mettle::resolution::resolve(tree, diagnostics, ownership);
  require(symbols && diagnostics.empty() && !tree.functions.empty() &&
              symbols->packageOf(tree.functions.front().span) == 0,
          "known root fixture did not receive ordinary package zero");
  require(mettle::check(std::move(tree), diagnostics, symbols).has_value() &&
              diagnostics.empty(),
          "known matching package zero was rejected as unknown");
}

void crossPackageReexportsPreserveOwnership() {
  for (bool foreign : {false, true}) {
    std::vector<mettle::Source> sources{
        {"memory/root.mt",
         std::string("import remote.relay.{Foreign, Remote};\n") +
             (foreign
                  ? "alias Alias = Remote;\n"
                    "extend Alias implements Foreign {}\n"
                    "extend<region r> read Alias from r implements Foreign {}\n"
                  : "interface Local {}\ntype Owned {}\n"
                    "extend Remote implements Local {}\n"
                    "extend Owned implements Foreign {}\n"
                    "extend<region r> read Owned from r implements Foreign {}\n"
                    "extend<region r> mut Owned from r implements Foreign "
                    "{}\n") +
             "fn main(): i32 { 0 }\n"},
        {"memory/foreign/main.mt",
         "pub interface Foreign {}\npub type Remote {}\n"
         "extend bool implements Foreign {}\n"
         "unsafe extend Remote implements Unpin {}\n"
         "pub module relay { pub import super.{Foreign, Remote}; }\n"}};
    mettle::resolution::Library library;
    library.rootIdentity = "fixture-root";
    mettle::resolution::Library::Package dependency;
    dependency.name = "remote";
    dependency.source = "memory/foreign/main.mt";
    dependency.module = "pkg_foreign";
    dependency.instanceIdentity = "fixture-foreign";
    library.packages.push_back(std::move(dependency));
    library.packageDependencies = {{"remote", "pkg_foreign"}};
    mettle::Diagnostics diagnostics;
    auto compiled = mettle::pipeline::compile(sources, diagnostics, library);
    if (!foreign) {
      require(compiled.has_value() && diagnostics.empty(),
              "known local interface/type failed through a foreign reexport");
      continue;
    }
    require(!compiled &&
                std::any_of(
                    diagnostics.items.begin(), diagnostics.items.end(),
                    [](const auto &item) {
                      return item.phase == "type" && item.severity == "error" &&
                             item.message.find(
                                 "orphan interface implementation has no local "
                                 "owner") != std::string::npos;
                    }),
            "foreign alias/reexport created a local owner or failed elsewhere");
  }
}

void syntaxAndIdentities() {
  mettle::Source source{"memory/root.mt",
                        "module left { pub fn value() { 20 } }\n"
                        "module right { pub fn value() { 22 } }\n"
                        "import left.value as first;\n"
                        "fn main() { first() + right.value() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(), "module resolution failed");
  require(tree.functions[0].name == "value" &&
              tree.functions[1].name == "value",
          "resolution rewrote syntax declaration names");
  auto left = resolved->moduleOf(tree.functions[0].span);
  auto right = resolved->moduleOf(tree.functions[1].span);
  require(left != right, "distinct modules share an identity");
  require(resolved->canonical(tree.functions[0].span) == "left::value",
          "missing canonical definition side table");
  require(resolved->lookup(0, "first", mettle::resolution::Namespace::Value,
                           {}) == "left::value",
          "import alias did not preserve declaration identity");
  require(resolved->lookup(right, "super::left::value",
                           mettle::resolution::Namespace::Value,
                           {}) == "left::value",
          "super path did not resolve from declaration scope");
}

void sameDeclarationGlobs() {
  mettle::Source source{"memory/root.mt",
                        "module base { pub fn answer() { 42 } }\n"
                        "module a { pub import main.base.answer; }\n"
                        "module b { pub import main.base.answer; }\n"
                        "import a.*;\nimport b.*;\nfn main() { answer() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(),
          "two glob paths to one declaration became ambiguous");
}

void delayedExplicitImport() {
  mettle::Source source{"memory/root.mt",
                        "module a { pub fn answer() { 1 } }\n"
                        "module b { pub fn answer() { 42 } }\n"
                        "module selected {\n"
                        "pub import main.a.*;\n"
                        "pub import main.relay.answer;\n}\n"
                        "module relay { pub import main.b.answer; }\n"
                        "import selected.*;\nfn main() { answer() }\n"};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(source, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(),
          "glob export raced an unresolved explicit import");
  require(resolved->lookup(0, "answer", mettle::resolution::Namespace::Value,
                           {}) == "b::answer",
          "import order changed explicit binding selection");
}

void dependentImportWorklist() {
  std::string source;
  for (unsigned i = 0; i < 128; ++i)
    source += "module relay" + std::to_string(i) + " { pub import main.relay" +
              std::to_string(i + 1) + ".*; }\n";
  source += "module relay128 { pub fn answer() { 42 } "
            "pub import main.relay128.*; }\n"
            "import relay0.answer;\nfn main() { answer() }\n";
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse({"memory/reexports.mt", source}, diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  require(resolved && diagnostics.empty(),
          "reverse reexports and a self glob did not reach a fixed point");
  require(resolved->lookup(0, "answer", mettle::resolution::Namespace::Value,
                           {}) == "relay128::answer",
          "dependent reexports lost their canonical declaration");
}

void sourceDiagnostic() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "module child;\nfn main() { 0 }\n"},
      {"memory/child.mt", "fn invalid() { let x = ; }\n"}};
  mettle::Diagnostics diagnostics;
  require(!mettle::resolution::load(sources, diagnostics),
          "malformed external source was accepted");
  std::ostringstream rendered;
  diagnostics.print(sources.front(), rendered);
  require(rendered.str().find("memory/child.mt:1:") != std::string::npos,
          "external diagnostic lost its source identity");
}

void duplicateFileIdentity() {
  mettle::Diagnostics diagnostics;
  mettle::resolution::SourceProvider provider =
      [](const std::string &path) -> std::optional<mettle::Source> {
    if (path == "memory/one.mt" || path == "memory/two.mt")
      return mettle::Source{"memory/same.mt", "pub fn value() { 42 }\n"};
    return std::nullopt;
  };
  auto tree = mettle::resolution::load(
      {"memory/root.mt", "module one;\nmodule two;\n"}, provider, diagnostics);
  require(!tree && !diagnostics.empty(),
          "one source acquired two module identities");
}

void privateRootReexport() {
  mettle::Diagnostics diagnostics;
  auto tree = mettle::parse(
      {"memory/root.mt", "fn hidden() { 42 }\npub import hidden as exposed;\n"},
      diagnostics);
  require(!mettle::resolution::resolve(tree, diagnostics),
          "package-private root declaration became globally public");
  require(!diagnostics.empty() && diagnostics.items.back().message.find(
                                      "cannot reexport") != std::string::npos,
          "private reexport failed for an unrelated reason");
}

void associatedImports() {
  mettle::Diagnostics diagnostics;
  auto tree =
      mettle::parse({"memory/root.mt",
                     "pub enum Choice { Answer(i32), Empty }\n"
                     "type Maker { pub static fn answer() { 42 }; drop {} }\n"
                     "alias Alias = Choice;\n"
                     "import Alias.{Answer as result};\n"
                     "import Choice.*;\n"
                     "import Maker.answer as get;\n"},
                    diagnostics);
  auto resolved = mettle::resolution::resolve(tree, diagnostics);
  if (!resolved)
    diagnostics.print({"memory/root.mt", ""}, std::cerr);
  require(resolved && diagnostics.empty(), "associated import failed");
  require(resolved->lookup(0, "result", mettle::resolution::Namespace::Value,
                           {}) == "Choice::Answer",
          "alias variant import lost the nominal declaration");
  require(resolved->lookup(0, "Empty", mettle::resolution::Namespace::Value,
                           {}) == "Choice::Empty",
          "enum variant glob did not resolve");
  require(resolved->lookup(0, "get", mettle::resolution::Namespace::Value,
                           {}) == "Maker.answer",
          "associated function import did not resolve");
  require(!resolved->lookup(0, "Maker::drop",
                            mettle::resolution::Namespace::Value, {}),
          "destructor was exposed as an associated callable binding");
}
void macroDefinitionSiteMountsOnlyReferencedNativeNamespace() {
  for (bool definitionReference : {true, false}) {
    std::vector<mettle::Source> sources{
        {"memory/main.mt", "fn main(): i32 { core.answer!() - 42 }\n"},
        {"memory/lib/core/module.mt",
         std::string("fn secret(): i32 { 42 }\npub macro answer { () => { ") +
             (definitionReference ? "secret()" : "{ let value = 42; value }") +
             " }; }\n"}};
    mettle::resolution::Library library;
    library.directory = "memory/lib";
    mettle::resolution::SourcePackages ownership;
    mettle::Diagnostics diagnostics;
    auto tree =
        mettle::resolution::load(sources, diagnostics, library, &ownership);
    if (!tree)
      diagnostics.print(sources.front(), std::cerr);
    require(tree && diagnostics.empty(),
            "native macro hygiene fixture failed loading");
    auto main = std::find_if(
        tree->functions.begin(), tree->functions.end(),
        [](const auto &function) { return function.name == "main"; });
    require(main != tree->functions.end(),
            "native macro hygiene fixture lost main");
    require(std::none_of(tree->tokens.begin(), tree->tokens.end(),
                         [&](const auto &token) {
                           return token.span.source == main->span.source &&
                                  token.text == "core";
                         }),
            "expanded main retained an explicit core token");
    auto symbols = mettle::resolution::resolve(*tree, diagnostics, ownership);
    if (!symbols)
      diagnostics.print(sources.front(), std::cerr);
    require(symbols && diagnostics.empty(),
            "native macro hygiene fixture failed resolution");
    auto secret = std::find_if(
        tree->functions.begin(), tree->functions.end(),
        [](const auto &function) { return function.name == "secret"; });
    if (definitionReference) {
      require(secret != tree->functions.end(),
              "definition-site reference did not load private secret");
      require(!secret->item.visibility.publicItem &&
                  symbols->canonical(secret->span) == "core::secret",
              "private macro dependency lost its core definition namespace");
    } else {
      require(secret == tree->functions.end() &&
                  std::none_of(symbols->modules().begin(),
                               symbols->modules().end(),
                               [](const auto &module) {
                                 return module.canonical == "core";
                               }),
              "macro-local binding unnecessarily mounted core");
    }
    auto checked = mettle::check(std::move(*tree), diagnostics, symbols);
    if (!checked)
      diagnostics.print(sources.front(), std::cerr);
    require(checked.has_value() && diagnostics.empty(),
            "native macro definition-site or local binding failed checking");
  }
  std::vector<mettle::Source> sources{
      {"memory/main.mt", "core.generate!()\n"
                         "fn main(): i32 { identity(value: 42) - 42 }\n"},
      {"memory/lib/core/module.mt",
       "pub macro generate { () => { "
       "fn identity<T>(take value: T): T { value } }; }\n"}};
  mettle::resolution::Library library;
  library.directory = "memory/lib";
  mettle::resolution::SourcePackages ownership;
  mettle::Diagnostics diagnostics;
  auto tree =
      mettle::resolution::load(sources, diagnostics, library, &ownership);
  if (!tree)
    diagnostics.print(sources.front(), std::cerr);
  require(tree && diagnostics.empty(),
          "macro-local generic fixture failed loading");
  auto main = std::find_if(
      tree->functions.begin(), tree->functions.end(),
      [](const auto &function) { return function.name == "main"; });
  require(main != tree->functions.end(),
          "macro-local generic fixture lost main");
  require(std::none_of(tree->tokens.begin(), tree->tokens.end(),
                       [&](const auto &token) {
                         return token.span.source == main->span.source &&
                                token.text == "core";
                       }),
          "expanded generic fixture retained an explicit core token");
  auto symbols = mettle::resolution::resolve(*tree, diagnostics, ownership);
  if (!symbols)
    diagnostics.print(sources.front(), std::cerr);
  require(symbols && diagnostics.empty(),
          "macro-local generic fixture failed resolution");
  require(std::none_of(
              symbols->modules().begin(), symbols->modules().end(),
              [](const auto &module) { return module.canonical == "core"; }),
          "macro-local generic, parameter or argument label mounted core");
  auto checked = mettle::check(std::move(*tree), diagnostics, symbols);
  if (!checked)
    diagnostics.print(sources.front(), std::cerr);
  require(checked.has_value() && diagnostics.empty(),
          "macro-local generic, parameter or argument label failed checking");
  std::vector<mettle::Source> fieldSources{
      {"memory/main.mt",
       "type Slot { pub value: i32 }\n"
       "fn main(): i32 { let slot = Slot(42); core.field!(slot) - 42 }\n"},
      {"memory/lib/core/module.mt",
       "pub macro field { ($value:expr) => { $value.value }; }\n"}};
  mettle::resolution::Library fieldLibrary;
  fieldLibrary.directory = "memory/lib";
  mettle::resolution::SourcePackages fieldOwnership;
  mettle::Diagnostics fieldDiagnostics;
  auto fieldTree = mettle::resolution::load(fieldSources, fieldDiagnostics,
                                            fieldLibrary, &fieldOwnership);
  if (!fieldTree)
    fieldDiagnostics.print(fieldSources.front(), std::cerr);
  require(fieldTree && fieldDiagnostics.empty(),
          "captured receiver and authored public field failed loading");
  auto fieldMain = std::find_if(
      fieldTree->functions.begin(), fieldTree->functions.end(),
      [](const auto &function) { return function.name == "main"; });
  require(fieldMain != fieldTree->functions.end(),
          "public field macro fixture lost main");
  require(std::none_of(fieldTree->tokens.begin(), fieldTree->tokens.end(),
                       [&](const auto &token) {
                         return token.span.source == fieldMain->span.source &&
                                token.text == "core";
                       }),
          "expanded public field fixture retained an explicit core token");
  auto fieldSymbols =
      mettle::resolution::resolve(*fieldTree, fieldDiagnostics, fieldOwnership);
  if (!fieldSymbols)
    fieldDiagnostics.print(fieldSources.front(), std::cerr);
  require(fieldSymbols && fieldDiagnostics.empty(),
          "captured receiver and authored public field failed resolution");
  require(std::none_of(
              fieldSymbols->modules().begin(), fieldSymbols->modules().end(),
              [](const auto &module) { return module.canonical == "core"; }),
          "authored public field selector unnecessarily mounted core");
  auto fieldChecked =
      mettle::check(std::move(*fieldTree), fieldDiagnostics, fieldSymbols);
  if (!fieldChecked)
    fieldDiagnostics.print(fieldSources.front(), std::cerr);
  require(fieldChecked.has_value() && fieldDiagnostics.empty(),
          "captured receiver and authored public field failed checking");
}

void macroDefinitionSiteReplaysQualifiedRootSource() {
  const mettle::Source root{"memory/main.mt",
                            "fn main(): i32 { hidden.answer!() - 42 }\n"};
  const std::string selected =
      "fn secret(): i32 { 42 }\npub macro answer { () => { secret() }; }\n";
  unsigned decoyReads = 0;
  mettle::resolution::SourceProvider provider =
      [&](const std::string &path) -> std::optional<mettle::Source> {
    if (path == "memory/hidden/module.mt")
      return mettle::Source{path, selected};
    if (path == "memory/hidden/main.mt") {
      ++decoyReads;
      return mettle::Source{path, "fn secret(): i32 { 7 }\n"
                                  "pub macro answer { () => { secret() }; }\n"};
    }
    return std::nullopt;
  };
  mettle::resolution::Library library;
  std::vector<mettle::resolution::SourceModule> sourceModules, allSources;
  mettle::resolution::SourcePackages ownership;
  mettle::Diagnostics diagnostics;
  auto tree = mettle::resolution::load(root, provider, diagnostics, library,
                                       &sourceModules, &allSources, &ownership);
  if (!tree)
    diagnostics.print(root, std::cerr);
  require(tree && diagnostics.empty(),
          "qualified macro definition-site replay failed loading");
  require(decoyReads == 0, "qualified macro replay probed the main.mt decoy");
  for (const auto *catalog : {&sourceModules, &allSources}) {
    auto source =
        std::find_if(catalog->begin(), catalog->end(), [](const auto &entry) {
          return entry.source.path == "memory/hidden/module.mt";
        });
    require(source != catalog->end() &&
                source->path == std::vector<std::string>{"hidden"} &&
                source->packageIdentity.empty() &&
                source->source.text == selected,
            "replayed macro source lost its root-package catalog identity");
    require(std::none_of(catalog->begin(), catalog->end(),
                         [](const auto &entry) {
                           return entry.source.path == "memory/hidden/main.mt";
                         }),
            "root-package source catalog adopted the main.mt decoy");
  }
  auto symbols = mettle::resolution::resolve(*tree, diagnostics, ownership);
  if (!symbols)
    diagnostics.print(root, std::cerr);
  require(symbols && diagnostics.empty(),
          "qualified macro definition-site replay failed resolution");
  auto secret = std::find_if(
      tree->functions.begin(), tree->functions.end(),
      [](const auto &function) { return function.name == "secret"; });
  require(secret != tree->functions.end() &&
              !secret->item.visibility.publicItem &&
              symbols->canonical(secret->span) == "hidden::secret",
          "qualified macro replay lost its private definition namespace");
  const auto &value = singleValue(secret->body.get());
  require(value.kind == mettle::Kind::Integer && value.text == "42",
          "qualified macro replay used the decoy secret body");
  auto checked = mettle::check(std::move(*tree), diagnostics, symbols);
  if (!checked)
    diagnostics.print(root, std::cerr);
  require(checked.has_value() && diagnostics.empty(),
          "qualified macro definition-site replay failed checking");
}

void missingMacroDefinitionNamespaceCannotAccessPrivateField() {
  std::vector<mettle::Source> sources{
      {"memory/main.mt",
       "type Slot { value: i32 }\n"
       "fn main(): i32 { let slot = Slot(42); core.field!(slot) - 42 }\n"},
      {"memory/lib/core/module.mt",
       "pub macro field { ($value:expr) => { $value.value }; }\n"}};
  mettle::resolution::Library library;
  library.directory = "memory/lib";
  mettle::resolution::SourcePackages ownership;
  mettle::Diagnostics diagnostics;
  auto tree =
      mettle::resolution::load(sources, diagnostics, library, &ownership);
  if (!tree)
    diagnostics.print(sources.front(), std::cerr);
  require(tree && diagnostics.empty(), "private field macro failed loading");
  auto main = std::find_if(
      tree->functions.begin(), tree->functions.end(),
      [](const auto &function) { return function.name == "main"; });
  require(main != tree->functions.end(), "private field macro lost main");
  require(std::none_of(tree->tokens.begin(), tree->tokens.end(),
                       [&](const auto &token) {
                         return token.span.source == main->span.source &&
                                token.text == "core";
                       }),
          "expanded private field fixture retained an explicit core token");
  auto symbols = mettle::resolution::resolve(*tree, diagnostics, ownership);
  if (!symbols)
    diagnostics.print(sources.front(), std::cerr);
  require(symbols && diagnostics.empty(),
          "private field macro failed before visibility checking");
  require(std::none_of(
              symbols->modules().begin(), symbols->modules().end(),
              [](const auto &module) { return module.canonical == "core"; }),
          "private field selector unnecessarily mounted core");
  auto checked = mettle::check(std::move(*tree), diagnostics, symbols);
  require(!checked.has_value(),
          "missing macro namespace inherited caller-root private authority");
  require(std::any_of(diagnostics.items.begin(), diagnostics.items.end(),
                      [](const auto &diagnostic) {
                        return diagnostic.severity == "error" &&
                               diagnostic.phase == "name" &&
                               diagnostic.message ==
                                   "private or restricted field 'value' is "
                                   "inaccessible";
                      }),
          "private field macro failed without its visibility diagnostic");
}

void macroRegionOccurrencesRetainBindingIdentity() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt",
       "macro captured { ($r:ident) => {\n"
       "  for<region r> fn(read i32 from $r): Unit\n"
       "}; }\n"
       "macro authored { () => {\n"
       "  for<region r> fn(read i32 from r): Unit\n"
       "}; }\n"
       "macro whole { ($t:ty) => { for<region r> fn(read $t): Unit }; }\n"
       "fn inspect_captured<region r>(read anchor: i32 from r,\n"
       "  callback: captured!(r)) {}\n"
       "fn inspect_authored<region r>(read anchor: i32 from r,\n"
       "  callback: authored!()) {}\n"
       "fn inspect_whole<region r>(read anchor: i32 from r,\n"
       "  callback: whole!(i32 from r)) {}\n"
       "macro outer { () => {\n"
       "  fn $capture(inspect_nested)<region r>(read anchor: i32 from r,\n"
       "    callback: captured!(r)) {}\n"
       "}; }\n"
       "outer!()\n"
       "macro split { ($input:ident) => {\n"
       "  fn $capture(inspect_sources)(read $input: i32, read input: i32): "
       "    (read i32 from $input, read i32 from input) {\n"
       "      (read $input, read input)\n"
       "  }\n"
       "}; }\n"
       "split!(input)\n"
       "fn main(): i32 { 0 }\n"}};
  mettle::Diagnostics diagnostics;
  auto tree = mettle::resolution::load(sources, diagnostics);
  if (!tree)
    diagnostics.print(sources.front(), std::cerr);
  require(tree && diagnostics.empty(), "region hygiene fixture failed loading");
  auto symbols = mettle::resolution::resolve(*tree, diagnostics);
  require(symbols && diagnostics.empty(),
          "region hygiene fixture failed name resolution");
  auto checked = mettle::check(std::move(*tree), diagnostics, symbols);
  if (!checked)
    diagnostics.print(sources.front(), std::cerr);
  require(checked && diagnostics.empty(),
          "region hygiene fixture failed semantic checking");
  const auto &functions = checked->syntax().functions;
  const auto &types = *checked->typeStore();
  for (const auto &[name, authored] :
       {std::pair{"inspect_captured", false},
        std::pair{"inspect_authored", true}, std::pair{"inspect_whole", false},
        std::pair{"inspect_nested", false}}) {
    auto function = std::find_if(
        functions.begin(), functions.end(),
        [&](const auto &candidate) { return candidate.name == name; });
    require(function != functions.end(),
            "region hygiene fixture lost function");
    auto index = static_cast<std::size_t>(function - functions.begin());
    const auto &signature =
        types.callable(checked->function(index).regionSignature);
    require(signature.parameterRegions.size() == 2 &&
                signature.parameters.size() == 2,
            "region fixture lost its outer parameter regions");
    auto outer = signature.parameterRegions[0];
    require(outer != mettle::RegionId::Unspecified,
            "outer region was not resolved");
    const auto &callback = types.callable(signature.parameters[1].type);
    require(callback.regionParameters.size() == 1 &&
                callback.parameterRegions.size() == 1,
            "region fixture lost its callable binder");
    auto inner = callback.regionParameters[0];
    require(inner != mettle::RegionId::Unspecified && inner != outer,
            "authored region captured the outer binder identity");
    require(callback.parameterRegions[0] == (authored ? inner : outer),
            "from occurrence selected the wrong same-spelled region binder");
    if (std::string_view(name) == "inspect_nested")
      require(function->genericParameters[0].context &&
                  function->genericParameters[0].context->identity != 0,
              "nested capture control lost its nonzero outer expansion mark");
  }
  auto split = std::find_if(
      functions.begin(), functions.end(),
      [](const auto &function) { return function.name == "inspect_sources"; });
  require(split != functions.end(),
          "region fixture lost its nested-source case");
  auto index = static_cast<std::size_t>(split - functions.begin());
  const auto &facts = checked->function(index);
  require(facts.resultSources == std::vector<std::size_t>{0, 1},
          "nested result sources collapsed same-spelled lexical identities");
  const auto &signature = types.callable(facts.regionSignature);
  require(signature.parameterRegions.size() == 2 &&
              signature.parameterRegions[0] != mettle::RegionId::Unspecified &&
              signature.parameterRegions[1] != mettle::RegionId::Unspecified &&
              signature.parameterRegions[0] != signature.parameterRegions[1],
          "same-spelled parameter bindings shared a region identity");
  const auto &result = types.product(signature.result);
  require(result.components.size() == 2 && types.isView(result.components[0]) &&
              types.isView(result.components[1]),
          "nested result-source views were not retained");
  require(types.view(result.components[0]).region ==
                  signature.parameterRegions[0] &&
              types.view(result.components[1]).region ==
                  signature.parameterRegions[1],
          "nested from occurrences lost their distinct parameter regions");
}

void catalogLibrary() {
  std::vector<mettle::Source> sources{
      {"memory/root.mt", "fn main() { core.answer() - 42 }\n"},
      {"memory/lib/core/module.mt", "pub fn answer() { 42 }\n"},
      {"memory/lib/std/module.mt", "pub fn broken() { missing() }\n"}};
  mettle::resolution::Library library;
  library.directory = "memory/lib";
  mettle::Diagnostics diagnostics;
  require(mettle::pipeline::compile(sources, diagnostics, library).has_value(),
          "catalog-supplied library failed or loaded an unreferenced root");
  sources.front().text = "fn main() { std.broken() }\n";
  mettle::Diagnostics failing;
  require(!mettle::pipeline::compile(sources, failing, library).has_value(),
          "referenced library error was not reported");
}

void compiledClosuresReplaceHeadersAndRespectShadows() {
  for (bool shadow : {false, true}) {
    mettle::Diagnostics diagnostics;
    mettle::resolution::Library library;
    library.directory = "memory/lib";
    library.compiledSourceModules.emplace(1, std::vector<std::string>{"core"});
    library.compiledSourceModules.emplace(2, std::vector<std::string>{"alloc"});
    unsigned coreReads = 0, allocReads = 0, sourceReads = 0;
    auto header = [&](const std::string &text, mettle::SourceId id) {
      return mettle::parse({"memory/header.mt", text, id}, diagnostics);
    };
    library.compiled.push_back(
        {"core", [&] {
           ++coreReads;
           return header("pub module core { pub fn value(): i32 { 1 } }\n", 1);
         }});
    library.compiled.push_back(
        {"alloc",
         [&] {
           ++allocReads;
           return header("pub module core { pub fn value(): i32 { 2 } }\n"
                         "pub module alloc { pub fn value(): i32 { "
                         "core.value() + 40 } }\n",
                         2);
         },
         {},
         {"core"}});
    auto provider =
        [&](const std::string &path) -> std::optional<mettle::Source> {
      ++sourceReads;
      if (path == "memory/lib/alloc/module.mt")
        return mettle::Source{path,
                              "pub fn value(): i32 { core.value() + 40 }\n"};
      return std::nullopt;
    };
    auto text = shadow ? "module core { pub fn value(): i32 { 3 } }\n"
                         "fn main(): i32 { core.value() + alloc.value() }\n"
                       : "fn main(): i32 { core.value() + alloc.value() }\n";
    auto tree = mettle::resolution::load({"memory/root.mt", text}, provider,
                                         diagnostics, library);
    auto resolved =
        tree ? mettle::resolution::resolve(*tree, diagnostics) : nullptr;
    if (!resolved)
      diagnostics.print({"memory/root.mt", text}, std::cerr);
    require(resolved && diagnostics.empty() && tree->functions.size() == 3,
            "compiled closure duplicated declarations or failed resolution");
    require(
        shadow ? coreReads == 0 && allocReads == 0 && sourceReads > 0
               : coreReads == 1 && allocReads == 1 && sourceReads == 0,
        "compiled closure ignored a user dependency shadow or was not used");
    if (!shadow) {
      auto core = std::find_if(tree->functions.begin(), tree->functions.end(),
                               [](const auto &function) {
                                 return function.item.scope ==
                                        std::vector<std::string>{"core"};
                               });
      require(core != tree->functions.end() && core->span.source == 2,
              "smaller compiled header survived closure replacement");
    }
  }
}

void recursiveRegionCoercionKeepsTypeDescriptors() {
  for (unsigned padding = 0; padding < 32; ++padding) {
    mettle::TypeStore types;
    for (unsigned i = 0; i < padding; ++i)
      types.declareProduct("Padding" + std::to_string(i), true);
    auto callable = [&] {
      auto scope = types.regions().binder();
      auto region = types.regions().bound(scope, "r");
      auto result = types.structural(
          mettle::AggregateKind::Tuple,
          {types.viewType(mettle::Type::I32, mettle::ParameterMode::Read,
                          region)});
      mettle::CallableType descriptor;
      descriptor.parameters.push_back(
          {mettle::Type::I32, mettle::ParameterMode::Read, "input"});
      descriptor.parameterRegions.push_back(region);
      descriptor.regionParameters.push_back(region);
      descriptor.result = result;
      descriptor.abiResult = result;
      descriptor.resultSources.push_back(0);
      return types.callableType(std::move(descriptor));
    };
    auto source = types.structural(mettle::AggregateKind::Tuple,
                                   {callable(), mettle::Type::I32});
    auto target = types.structural(mettle::AggregateKind::Tuple,
                                   {callable(), mettle::Type::I32});
    mettle::RegionSolver regions(types.regions());
    mettle::RegionTypeSolver solver(types, regions);
    require(solver.coerce(source, target, {}) == mettle::RegionAnswer::Proven,
            "recursive callable coercion lost its type descriptors");
  }
  {
    mettle::TypeStore types;
    auto callable = [&](bool staticPayload) {
      auto scope = types.regions().binder();
      auto borrow = types.regions().bound(scope, "borrow");
      auto element = staticPayload ? mettle::RegionId::Static
                                   : types.regions().bound(scope, "element");
      mettle::CallableType descriptor;
      descriptor.parameters.push_back(
          {types.sliceType(types.viewType(
               mettle::Type::I32, mettle::ParameterMode::Read, element)),
           mettle::ParameterMode::Mut, "input"});
      descriptor.parameterRegions.push_back(borrow);
      descriptor.regionParameters.push_back(borrow);
      if (!staticPayload)
        descriptor.regionParameters.push_back(element);
      descriptor.result = mettle::Type::Unit;
      descriptor.abiResult = mettle::Type::Unit;
      return types.callableType(std::move(descriptor));
    };
    mettle::RegionSolver regions(types.regions());
    mettle::RegionTypeSolver solver(types, regions);
    auto target = callable(false);
    require(solver.coerce(callable(false), target, {}) ==
                mettle::RegionAnswer::Proven,
            "callable region inference did not descend into slice elements");
    require(solver.coerce(callable(true), target, {}) ==
                mettle::RegionAnswer::Rejected,
            "higher-ranked slice coercion accepted a static-only payload");
  }
}

void interfaceSolversRespectTypeStoresAndMutations() {
  using namespace mettle;
  TypeStore base;
  auto self = base.declareParameter("Self", false);
  auto parameter = base.declareParameter("T", false);
  ErasedType descriptor;
  descriptor.name = "Marker";
  auto interface = base.erasedType(descriptor);

  interfaces::Database database;
  interfaces::Definition definition;
  definition.name = "Marker";
  definition.self = self;
  database.definitions.push_back(std::move(definition));
  interfaces::Implementation implementation;
  implementation.target = parameter;
  implementation.interfaceType = interface;
  implementation.parameters.push_back(parameter);
  implementation.requirements.push_back(
      {parameter, Type::Unknown, interfaces::Property::Copy});
  database.implementations.push_back(std::move(implementation));
  database.argumentsReady = true;

  TypeStore first = base;
  TypeStore second = base;
  auto copy = first.declareProduct("Copy", true);
  auto noncopy = second.declareProduct("NonCopy", false);
  require(copy == noncopy, "type-store cache fixture did not collide");
  Diagnostics diagnostics;
  interfaces::Solver firstSolver(first, database, diagnostics);
  interfaces::Solver secondSolver(second, database, diagnostics);
  require(firstSolver.prove({copy, interface}, {}, false),
          "Copy-constrained implementation was not selected");
  require(!secondSolver.prove({noncopy, interface}, {}, false),
          "interface cache reused a result from a different type store");

  database.implementations[0].requirements.clear();
  interfaces::Solver updatedSolver(second, database, diagnostics);
  require(updatedSolver.prove({noncopy, interface}, {}, false),
          "interface solver reused a result after the implementation changed");

  database.implementations[0].requirements.push_back(
      {parameter, Type::Unknown, interfaces::Property::Copy});
  TypeStore third = base;
  auto changing = third.declareProduct("Changing", true);
  auto member = third.declareProduct("Member", false);
  third.setGenericParameters(changing, {member});
  interfaces::Solver beforeMutation(third, database, diagnostics);
  require(beforeMutation.prove({changing, interface}, {}, false),
          "unconditional Copy implementation was not selected");
  third.setConditionalCopy(changing, {0});
  interfaces::Solver afterMutation(third, database, diagnostics);
  require(!afterMutation.prove({changing, interface}, {}, false),
          "interface solver reused a result after the type store changed");
}
} // namespace

int main() {
  dependentImportWorklist();
  try {
    demandLoadedFunctionContracts();
    demandLoadedDeclarationHeaders();
    unitLiteralKeepsSource();
    inMemorySources();
    residentFunctionQueries();
    ordinaryImportsDoNotLoadMacroModules();
    localMacroDoesNotDiscoverOrdinaryImports();
    demandedMacroReexportSkipsValueImportCycle();
    selectedMacroImportCycleTerminatesWithoutRepeatedReads();
    missingQualifiedMacroDiscoveryIsMemoized();
    macroDiscoveryDistinguishesProviderKinds();
    importedDirectoryModulesLoadModuleFile();
    unknownOwnershipCannotGrantLocality();
    crossPackageReexportsPreserveOwnership();
    syntaxAndIdentities();
    sameDeclarationGlobs();
    delayedExplicitImport();
    sourceDiagnostic();
    duplicateFileIdentity();
    privateRootReexport();
    associatedImports();
    macroDefinitionSiteMountsOnlyReferencedNativeNamespace();
    macroDefinitionSiteReplaysQualifiedRootSource();
    missingMacroDefinitionNamespaceCannotAccessPrivateField();
    macroRegionOccurrencesRetainBindingIdentity();
    recursiveRegionCoercionKeepsTypeDescriptors();
    interfaceSolversRespectTypeStoresAndMutations();
    catalogLibrary();
    compiledClosuresReplaceHeadersAndRespectShadows();
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
