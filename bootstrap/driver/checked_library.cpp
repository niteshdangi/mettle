#include "driver/checked_library.h"
#include "driver/cache.h"
#include "ir/codec.h"
#include "lowering/scalar.h"
#include "metadata/type_graph.h"
#include "resolution/resolve.h"
#include "support/limits.h"
#include <algorithm>
#include <array>
#include <charconv>
#include <iostream>
#include <limits>
#include <set>
#include <sstream>

namespace mettle::driver {
namespace {
using Symbol = std::pair<metadata::SymbolKind, std::uint32_t>;
using NamedSymbol = std::pair<metadata::SymbolKind, std::string>;
constexpr std::string_view nativePackage = "native:standard-library";
constexpr std::array<std::string_view, 3> nativeRoots{"core", "alloc", "std"};

std::string definitionSymbol(metadata::SymbolKind kind,
                             const std::string &definition) {
  return std::string(nativePackage) + ":" +
         std::to_string(static_cast<unsigned>(kind)) + ":" + definition;
}

std::string supportPrefix(std::string_view root, std::string_view key) {
  return std::string(nativePackage) + ":" + std::string(root) + ":" +
         std::string(key) + ":support:";
}
} // namespace

CheckedLibrary::CheckedLibrary(const Options &options, packages::Store &store,
                               expansion::Configuration configuration,
                               TargetFacts target)
    : archive(""), configuration(std::move(configuration)),
      target(std::move(target)), options(options), store(store) {}

bool CheckedLibrary::contains(std::string_view name) const {
  for (auto dependency : nativeRoots) {
    if (dependency == name)
      return true;
    if (dependency == root)
      break;
  }
  return false;
}

bool CheckedLibrary::prepareArchive(std::string &error) {
  lease = store.acquireLease(archiveKey);
  if (!lease) {
    error = "cannot acquire checked " + root + " cache lease";
    return false;
  }
  auto stored = store.data(archiveKey, limits::sourceBytes);
  if (stored.status == packages::Store::Lookup::Hit) {
    auto decoded = decodeLibraryArchive(stored.bytes, archiveKey, error);
    if (decoded) {
      archive = std::move(*decoded);
      if (options.explain)
        std::cerr << "mettle: checked library interface cache hit " << root
                  << " " << archiveKey.substr(0, 12) << '\n';
      return true;
    }
    if (options.explain)
      std::cerr << "mettle: checked library interface corrupt " << root << ": "
                << error << "; rebuilding\n";
    error.clear();
  } else if (stored.status == packages::Store::Lookup::Corrupt &&
             options.explain) {
    std::cerr << "mettle: checked library interface cache corrupt " << root
              << "; "
                 "rebuilding\n";
  }
  LibraryArchive candidate(archiveKey);
  Diagnostics diagnostics;
  expansion::MacroLibrary rules;
  resolution::Library library;
  library.directory = options.libraryDirectory;
  library.freestanding = options.freestanding;
  library.configuration = configuration;
  library.identifyMacroSource = [&](const Source &source) {
    auto revision = candidate.sources.record(source, error);
    return revision.value_or("");
  };
  library.macroExports = [&](const expansion::MacroLibrary &source) {
    auto remap = [&](const expansion::MacroSource &reference)
        -> std::optional<SourceId> {
      auto snapshot = candidate.sources.source(reference.identity);
      if (!snapshot || snapshot->path != reference.path ||
          snapshot->text.size() != reference.bytes)
        return std::nullopt;
      return snapshot->id;
    };
    return expansion::mergeMacros(rules, source, diagnostics, remap,
                                  library.identifyMacroSource);
  };
  Source bootstrap{(std::filesystem::path(options.libraryDirectory) /
                    ("__checked_" + root + "__.mt"))
                       .generic_string(),
                   "import " + root + " as checked_library_bootstrap\n"};
  auto provider = [&](const std::string &path) -> std::optional<Source> {
    std::error_code fileError;
    auto canonical = std::filesystem::weakly_canonical(path, fileError);
    if (fileError) {
      diagnostics.error("io", {},
                        "cannot identify " + path + ": " + fileError.message());
      return std::nullopt;
    }
    auto found = sourceInputs.find(canonical.generic_string());
    if (found == sourceInputs.end())
      return std::nullopt;
    return found->second;
  };
  std::vector<resolution::SourceModule> loaded;
  resolution::SourcePackages packages;
  auto tree = resolution::load(bootstrap, provider, diagnostics, library,
                               nullptr, &loaded, &packages);
  auto diagnose = [&]() {
    auto candidate = *receiverDiagnostics;
    std::map<SourceId, SourceId> sources;
    for (auto source : diagnostics.registeredSources()) {
      auto id = allocate();
      if (!id) {
        error = "checked-library diagnostic source identities exhausted";
        return false;
      }
      sources.emplace(source.id, id);
      source.id = id;
      Diagnostics::SourceContext context(candidate, source);
    }
    bool valid = true;
    auto remap = [&](Span span) {
      auto found = sources.find(span.source);
      if (found == sources.end())
        valid = false;
      else
        span.source = found->second;
      return span;
    };
    std::map<std::uint64_t, SyntaxContextPtr> contexts;
    for (auto generation : diagnostics.registeredGenerations()) {
      generation.source = remap({0, 0, generation.source}).source;
      generation.origin = remap(generation.origin);
      for (auto &mapping : generation.mappings) {
        mapping.target = remap(mapping.target);
        mapping.origin = remap(mapping.origin);
        if (mapping.syntaxContext && *mapping.syntaxContext) {
          const auto &original = **mapping.syntaxContext;
          auto [found, inserted] = contexts.try_emplace(original.identity);
          if (inserted)
            found->second = candidate.makeSyntaxContext(
                original.scope, remap(original.definition));
          mapping.syntaxContext = found->second;
        }
      }
      candidate.generated(std::move(generation));
    }
    for (auto diagnostic : diagnostics.items) {
      diagnostic.span = remap(diagnostic.span);
      for (auto &related : diagnostic.related)
        if (related.span)
          related.span = remap(*related.span);
      candidate.add(std::move(diagnostic.severity), std::move(diagnostic.phase),
                    diagnostic.span, std::move(diagnostic.message),
                    std::move(diagnostic.related));
    }
    if (!valid || diagnostics.empty()) {
      error = "checked-library failure has invalid or absent diagnostics";
      return false;
    }
    *receiverDiagnostics = std::move(candidate);
    error.clear();
    return false;
  };
  if (!tree)
    return diagnose();
  if (std::any_of(rules.definitions.begin(), rules.definitions.end(),
                  [](const auto &item) { return item.scope.empty(); }) ||
      std::any_of(rules.imports.begin(), rules.imports.end(),
                  [](const auto &item) { return item.scope.empty(); })) {
    error = "checked " + root + " has an unexpected root-scope macro inventory";
    return false;
  }
  std::erase(rules.indexedModules, "");
  std::erase_if(rules.declaredModules,
                [](const auto &path) { return path.empty(); });
  if (!candidate.sources.capture(diagnostics, error))
    return false;
  pipeline::PackageOwners owners;
  for (const auto &source : loaded) {
    if (source.path.empty())
      continue;
    if (!contains(source.path.front())) {
      error = "checked " + root + " depends on an undeclared native module";
      return false;
    }
    auto revision = candidate.sources.record(source.source, error);
    if (!revision)
      return false;
    candidate.sourceModules.emplace(*revision, source.path);
    owners.emplace(source.source.id, "native:" + source.path.front());
  }
  for (const auto &generation : diagnostics.registeredGenerations()) {
    auto scope = owners.find(generation.origin.source);
    if (scope != owners.end()) {
      owners.emplace(generation.source, scope->second);
      auto origin = candidate.sources.reference(generation.origin);
      auto generated =
          candidate.sources.reference(Span{0, 0, generation.source});
      if (!origin || !generated) {
        error = "checked " + root + " generation has no archived source";
        return false;
      }
      auto module = candidate.sourceModules.find(origin->revision);
      if (module == candidate.sourceModules.end()) {
        error = "checked " + root + " generation has no owning module";
        return false;
      }
      candidate.sourceModules.emplace(generated->revision, module->second);
    }
  }
  std::map<Symbol, std::string> symbols;
  std::map<Type, metadata::DefinitionIdentity> definitions;
  std::vector<Type> roots;
  std::map<Type, std::uint32_t> typeIndices;
  std::string referenceError;
  metadata::EncodeReferences references;
  references.source = [&](Span span) {
    auto reference = candidate.sources.reference(span);
    if (!reference)
      referenceError = "source " + std::to_string(span.source) + " at " +
                       std::to_string(span.begin) + ".." +
                       std::to_string(span.end) + " is not archived";
    return reference;
  };
  references.type = [&](Type type) -> std::optional<std::uint32_t> {
    auto [found, inserted] =
        typeIndices.emplace(type, static_cast<std::uint32_t>(roots.size()));
    if (inserted)
      roots.push_back(type);
    return found->second;
  };
  references.symbol = [&](metadata::SymbolKind kind,
                          std::uint32_t index) -> std::optional<std::string> {
    auto found = symbols.find({kind, index});
    return found == symbols.end() ? std::nullopt : std::optional(found->second);
  };
  std::size_t sourceFunctions = 0, defaultFunctions = 0;
  pipeline::CheckedObserver observe = [&](const CheckedModule &checked) {
    auto inventory = declarationInventory(checked);
    for (const auto &type : inventory.types)
      definitions.emplace(
          type.type,
          metadata::DefinitionIdentity{std::string(nativePackage),
                                       type.definition, type.parameterOrdinal});
    for (const auto &symbol : inventory.symbols) {
      auto identity =
          symbol.kind == metadata::SymbolKind::Package
              ? checked.namespaces().packageIdentity(symbol.index)
              : std::optional(definitionSymbol(symbol.kind, symbol.definition));
      if (!identity) {
        diagnostics.error("metadata", {},
                          "checked " + root + " package identity is missing");
        return;
      }
      symbols.emplace(Symbol{symbol.kind, symbol.index}, std::move(*identity));
    }
    sourceFunctions = checked.syntax().functions.size();
    for (std::size_t i = 0; i < sourceFunctions; ++i)
      for (std::size_t j = 0;
           j < checked.syntax().functions[i].parameters.size(); ++j)
        if (checked.hasDefault(i, j)) {
          auto function = symbols.find(
              {metadata::SymbolKind::Function, static_cast<std::uint32_t>(i)});
          if (function == symbols.end()) {
            diagnostics.error("metadata", {},
                              "checked " + root +
                                  " function identity is missing");
            return;
          }
          symbols.emplace(Symbol{metadata::SymbolKind::Function,
                                 static_cast<std::uint32_t>(
                                     sourceFunctions + defaultFunctions++)},
                          function->second + ":default:" + std::to_string(j));
        }
    constexpr std::array<SourceId, 1> omittedSources{0};
    auto declarations =
        exportLibraryDeclarations(checked, references, omittedSources);
    if (!declarations) {
      diagnostics.error("metadata", {},
                        declarations.error + (referenceError.empty()
                                                  ? ""
                                                  : ": " + referenceError));
      return;
    }
    candidate.header = std::move(declarations.header);
    candidate.declarations = std::move(declarations.contracts);
  };
  auto prepared = pipeline::prepare(std::move(*tree), diagnostics, false,
                                    target, observe, owners, numeric, packages);
  if (!prepared || !diagnostics.empty())
    return diagnose();
  if (!candidate.sources.capture(diagnostics, error))
    return false;
  const auto &program = prepared->program();
  auto supportBase = sourceFunctions + defaultFunctions;
  if (program.functions.size() < supportBase) {
    error = "checked " + root + " IR is missing a source/default definition";
    return false;
  }
  auto prefix = supportPrefix(root, archiveKey);
  for (std::size_t i = supportBase; i < program.functions.size(); ++i)
    symbols.emplace(
        Symbol{metadata::SymbolKind::Function, static_cast<std::uint32_t>(i)},
        prefix + std::to_string(i - supportBase));
  auto bodies = ir::encodeProgram(program, references);
  if (!bodies) {
    error =
        bodies.error + (referenceError.empty() ? "" : ": " + referenceError);
    return false;
  }
  candidate.ir = std::move(bodies.bytes);
  metadata::TypeGraphSymbols typeSymbols;
  typeSymbols.symbol = references.symbol;
  typeSymbols.definition =
      [&](Type type) -> std::optional<metadata::DefinitionIdentity> {
    auto found = definitions.find(type);
    return found == definitions.end() ? std::nullopt
                                      : std::optional(found->second);
  };
  auto graph = metadata::exportTypeGraph(*program.types, roots, typeSymbols);
  if (!graph) {
    error = graph.error;
    return false;
  }
  candidate.types = std::move(graph.bytes);
  auto macros = expansion::encodeMacros(rules, diagnostics);
  if (!macros)
    return diagnose();
  candidate.macros = std::move(*macros);
  auto encoded = encodeLibraryArchive(candidate, error);
  if (!encoded)
    return false;
  if (!store.putData(archiveKey, *encoded)) {
    error = "cannot publish checked " + root + " interface";
    return false;
  }
  archive = std::move(candidate);
  for (const auto &note : store.prune(archiveKey))
    if (options.explain)
      std::cerr << "mettle: " << note << '\n';
  if (options.explain)
    std::cerr << "mettle: checked library interface cache stored " << root
              << " " << archiveKey.substr(0, 12) << '\n';
  return true;
}

bool CheckedLibrary::mount(resolution::Library &library,
                           Diagnostics &diagnostics,
                           const expansion::SourceAllocator &allocate,
                           std::string &error) {
  error.clear();
  receiverLibrary = &library;
  receiverDiagnostics = &diagnostics;
  this->allocate = allocate;
  library.allocateSource = allocate;
  library.compiled.push_back({root, [this]() -> std::optional<Module> {
                                std::string error;
                                if (!ensureMounted(error)) {
                                  if (!error.empty())
                                    receiverDiagnostics->error("metadata", {},
                                                               error);
                                  return std::nullopt;
                                }
                                used = true;
                                return std::move(header.module);
                              }});
  auto previous = library.compiledMacros;
  library.compiledMacros = [this,
                            previous](const std::vector<std::string> &path,
                                      const std::vector<std::string> &from)
      -> std::optional<expansion::MacroModuleSource> {
    if (path.empty() || path.front() != root)
      return previous ? previous(path, from) : std::nullopt;
    return macroSource(path);
  };
  return true;
}

std::optional<expansion::MacroModuleSource>
CheckedLibrary::macroSource(const std::vector<std::string> &path) {
  std::string error;
  if (!ensureMounted(error)) {
    if (!error.empty())
      receiverDiagnostics->error("metadata", {}, error);
    return std::nullopt;
  }
  expansion::MacroModuleSource source;
  source.path = path;
  for (const auto &[revision, scope] : archive.sourceModules)
    if (scope.size() <= path.size() &&
        scope.size() > source.sourcePath.size() &&
        std::equal(scope.begin(), scope.end(), path.begin())) {
      auto snapshot = archive.sources.source(revision);
      if (!snapshot)
        return std::nullopt;
      source.source = {snapshot->path, "", snapshot->id};
      source.sourcePath = scope;
    }
  if (source.sourcePath.empty())
    return std::nullopt;
  source.configuration = configuration;
  source.compiled = macros;
  source.remapSources =
      [this](const expansion::MacroSource &source) -> std::optional<SourceId> {
    auto snapshot = archive.sources.source(source.identity);
    if (!snapshot || snapshot->path != source.path ||
        snapshot->text.size() != source.bytes)
      return std::nullopt;
    return snapshot->id;
  };
  return source;
}

bool CheckedLibrary::ensureMounted(std::string &error) {
  if (mounted)
    return true;
  if (unavailable) {
    error = "previous checked-library preparation failed";
    return false;
  }
  if (!prepareArchive(error)) {
    unavailable = true;
    return false;
  }
  auto &library = *receiverLibrary;
  auto &diagnostics = *receiverDiagnostics;
  auto candidate = diagnostics;
  if (!archive.sources.mount(
          candidate,
          [&]() -> std::optional<SourceId> {
            auto source = allocate();
            return source ? std::optional(source) : std::nullopt;
          },
          error))
    return false;
  metadata::DecodeReferences references;
  references.source = [&](const auto &reference) {
    return archive.sources.resolve(reference);
  };
  auto decoded = decodeLibraryHeader(archive.header, references);
  if (!decoded) {
    error = decoded.error;
    return false;
  }
  Diagnostics macroDiagnostics;
  auto rules = expansion::decodeMacros(archive.macros, macroDiagnostics);
  if (!rules) {
    std::ostringstream text;
    macroDiagnostics.print({}, text);
    error = text.str();
    return false;
  }
  for (const auto &source : rules->sources) {
    auto snapshot = archive.sources.source(source.identity);
    if (!snapshot || snapshot->path != source.path ||
        snapshot->text.size() != source.bytes) {
      error =
          "compiled macro source revision does not match the library archive";
      return false;
    }
  }
  header = std::move(decoded);
  functions = header.module->functions.size();
  statics = header.module->statics.size();
  interfaces = header.module->interfaces.size();
  for (std::size_t i = 0; i < functions; ++i)
    for (std::size_t j = 0; j < header.module->functions[i].parameters.size();
         ++j)
      if (header.module->functions[i].parameters[j].compiledDefault)
        defaults.emplace_back(static_cast<std::uint32_t>(i),
                              static_cast<std::uint32_t>(j));
  macros = std::make_shared<const expansion::MacroLibrary>(std::move(*rules));
  diagnostics = std::move(candidate);
  for (const auto &[revision, path] : archive.sourceModules) {
    auto source = archive.sources.source(revision);
    if (!source) {
      error = "compiled library module catalog refers to an absent source";
      return false;
    }
    library.compiledSourcePackages[source->id] = std::string(nativePackage);
    library.compiledSourceModules[source->id] = path;
  }
  mounted = true;
  return true;
}

pipeline::LibraryImporter CheckedLibrary::importer() {
  return [this](const Module &module, const resolution::Resolution &resolution,
                Diagnostics &diagnostics) {
    if (!used)
      return std::optional(pipeline::ImportedProgram{});
    return import(module, resolution, diagnostics);
  };
}

pipeline::PackageOwners CheckedLibrary::packageOwners() const {
  pipeline::PackageOwners owners;
  if (!used)
    return owners;
  for (const auto &[revision, path] : archive.sourceModules)
    if (auto source = archive.sources.source(revision))
      owners.emplace(source->id, "native:" + path.front());
  return owners;
}

std::string CheckedLibrary::sourcePath() const {
  for (const auto &[revision, path] : archive.sourceModules)
    if (path == std::vector<std::string>{root})
      if (auto source = archive.sources.source(revision))
        return source->path;
  return {};
}

std::optional<pipeline::ImportedProgram>
CheckedLibrary::import(const Module &module,
                       const resolution::Resolution &resolution,
                       Diagnostics &diagnostics) {
  auto fail = [&](const std::string &message)
      -> std::optional<pipeline::ImportedProgram> {
    diagnostics.error("metadata", {}, message);
    return std::nullopt;
  };
  if (module.functions.size() < functions || module.statics.size() < statics ||
      module.interfaces.size() < interfaces)
    return fail("compiled library header was not mounted before its consumer");
  std::map<NamedSymbol, std::uint32_t> symbols;
  std::vector<std::string> functionSymbols(functions);
  std::size_t closureCount = 0;
  for (const auto &symbol : header.symbols) {
    if (symbol.kind == metadata::SymbolKind::Package)
      continue;
    auto index = symbol.index;
    switch (symbol.kind) {
    case metadata::SymbolKind::Function:
      if (index >= functions)
        return fail("compiled function inventory exceeds the mounted header");
      functionSymbols[index] = symbol.definition;
      break;
    case metadata::SymbolKind::Interface:
      if (index >= interfaces)
        return fail("compiled interface inventory exceeds the mounted header");
      break;
    case metadata::SymbolKind::Static:
      if (index >= statics)
        return fail("compiled static inventory exceeds the mounted header");
      break;
    case metadata::SymbolKind::Closure:
      if (index >= limits::functions)
        return fail("compiled closure inventory exceeds the compiler limit");
      closureCount = std::max(closureCount, std::size_t(index) + 1);
      break;
    case metadata::SymbolKind::Package:
      break;
    }
    auto [found, inserted] =
        symbols.emplace(NamedSymbol{symbol.kind, symbol.definition}, index);
    if (!inserted && found->second != index)
      return fail("conflicting compiled declaration identities");
  }
  if (std::any_of(functionSymbols.begin(), functionSymbols.end(),
                  [](const auto &name) { return name.empty(); }))
    return fail("compiled function inventory is incomplete");
  std::map<std::pair<std::uint32_t, std::uint32_t>, std::uint32_t>
      defaultDestinations;
  std::size_t defaultCount = 0;
  for (std::size_t i = 0; i < module.functions.size(); ++i)
    for (std::size_t j = 0; j < module.functions[i].parameters.size(); ++j) {
      const auto &parameter = module.functions[i].parameters[j];
      if (!parameter.defaultValue.get() && !parameter.compiledDefault)
        continue;
      if (module.functions.size() + defaultCount >= limits::functions)
        return fail(
            "compiled default helpers exceed the compiler function limit");
      defaultDestinations.emplace(
          std::pair{static_cast<std::uint32_t>(i),
                    static_cast<std::uint32_t>(j)},
          static_cast<std::uint32_t>(module.functions.size() + defaultCount++));
    }
  for (auto [function, parameter] : defaults) {
    auto found = defaultDestinations.find({function, parameter});
    if (found == defaultDestinations.end())
      return fail("compiled default helper is absent from the mounted header");
    symbols.emplace(NamedSymbol{metadata::SymbolKind::Function,
                                functionSymbols[function] +
                                    ":default:" + std::to_string(parameter)},
                    found->second);
  }
  auto supportBase = module.functions.size() + defaultCount;
  auto prefix = supportPrefix(root, archiveKey);
  std::optional<std::uint32_t> largestSupportOrdinal;
  metadata::DecodeReferences references;
  references.source = [&](const auto &source) {
    return archive.sources.resolve(source);
  };
  references.symbol =
      [&](metadata::SymbolKind kind,
          std::string_view name) -> std::optional<std::uint32_t> {
    if (kind == metadata::SymbolKind::Package)
      return resolution.packageIndex(name);
    if (auto found = symbols.find({kind, std::string(name)});
        found != symbols.end())
      return found->second;
    if (kind != metadata::SymbolKind::Function || !name.starts_with(prefix))
      return std::nullopt;
    name.remove_prefix(prefix.size());
    std::uint32_t ordinal = 0;
    auto parsed =
        std::from_chars(name.data(), name.data() + name.size(), ordinal);
    if (parsed.ec != std::errc{} || parsed.ptr != name.data() + name.size() ||
        ordinal >= limits::functions ||
        supportBase + ordinal >= limits::functions)
      return std::nullopt;
    if (!largestSupportOrdinal || ordinal > *largestSupportOrdinal)
      largestSupportOrdinal = ordinal;
    return static_cast<std::uint32_t>(supportBase + ordinal);
  };
  auto types = std::make_shared<TypeStore>();
  types->setPointerBits(target.pointerBits);
  metadata::TypeGraphSymbols typeSymbols;
  typeSymbols.resolve = references.symbol;
  auto graph = metadata::importTypeGraph(*types, archive.types, typeSymbols);
  if (!graph)
    return fail(graph.error);
  references.type = [&](std::uint32_t reference) -> std::optional<Type> {
    if (reference >= graph.roots.size())
      return std::nullopt;
    return graph.roots[reference];
  };
  auto declarations =
      importLibraryDeclarations(archive.declarations, types, references);
  if (!declarations)
    return fail(declarations.error);
  if (declarations.declarations->closures.size() != closureCount)
    return fail("compiled closure declarations do not form the header prefix");
  auto decoded = ir::decodeProgram(archive.ir, references);
  if (!decoded)
    return fail(decoded.error);
  if (decoded.program.functions.size() < functions + defaults.size() ||
      decoded.program.statics.size() != statics)
    return fail("compiled IR definitions do not match the declaration header");
  auto supportCount =
      decoded.program.functions.size() - functions - defaults.size();
  if (largestSupportOrdinal && *largestSupportOrdinal >= supportCount)
    return fail("compiled support identity exceeds its artifact-local table");
  auto bodies = std::make_shared<lowering::ImportedBodies>();
  std::vector<std::optional<ir::Function>> support(supportCount);
  std::map<std::uint32_t, std::pair<std::uint32_t, std::uint32_t>>
      importedDefaults;
  for (auto entry : defaults)
    importedDefaults.emplace(defaultDestinations.at(entry), entry);
  std::set<std::uint32_t> assigned;
  for (std::size_t i = 0; i < decoded.program.functions.size(); ++i) {
    auto destination = decoded.functionDestinations[i];
    if (!assigned.insert(destination).second)
      return fail("duplicate compiled function destination");
    if (destination < functions) {
      if (decoded.functionIdentities[i] != functionSymbols[destination])
        return fail("compiled function identity does not match its header");
      bodies->functions.emplace(destination,
                                std::move(decoded.program.functions[i]));
    } else if (destination < supportBase) {
      auto found = importedDefaults.find(destination);
      if (found == importedDefaults.end())
        return fail("compiled body occupies a consumer default-helper slot");
      decoded.program.functions[i].name = decoded.functionIdentities[i];
      bodies->defaults.emplace(found->second,
                               std::move(decoded.program.functions[i]));
    } else if (destination - supportBase < supportCount) {
      decoded.program.functions[i].name = decoded.functionIdentities[i];
      support[destination - supportBase] =
          std::move(decoded.program.functions[i]);
    } else {
      return fail("compiled body destination exceeds its support table");
    }
  }
  if (bodies->functions.size() != functions ||
      bodies->defaults.size() != defaults.size())
    return fail("compiled IR is missing a source function or default helper");
  for (auto &function : support) {
    if (!function)
      return fail("compiled support destinations contain a gap");
    bodies->support.push_back(std::move(*function));
  }
  bodies->closureFunctions.assign(closureCount, -1);
  for (auto [slot, function] : decoded.closureFunctions) {
    if (slot >= closureCount || bodies->closureFunctions[slot] != -1)
      return fail(
          "compiled closure destinations conflict or exceed the header");
    bodies->closureFunctions[slot] = function;
  }
  if (std::any_of(bodies->closureFunctions.begin(),
                  bodies->closureFunctions.end(),
                  [](auto function) { return function < 0; }))
    return fail("compiled closure destinations contain a gap");
  for (std::size_t i = 0; i < decoded.staticDestinations.size(); ++i)
    if (decoded.staticDestinations[i] != i)
      return fail("compiled static destination does not match its header");
  decoded.program.functions.clear();
  decoded.program.functionPackages.clear();
  decoded.program.statics.clear();
  decoded.program.staticPackages.clear();
  decoded.program.types = types;
  pipeline::ImportedProgram imported;
  imported.declarations = std::move(declarations.declarations);
  imported.bodies = std::move(bodies);
  imported.metadata = std::move(decoded.program);
  return imported;
}

std::unique_ptr<CheckedLibraries> CheckedLibraries::create(
    const Options &options, const expansion::Configuration &configuration,
    packages::Store &store, TargetFacts target, NumericEvaluator numeric) {
  auto result = std::make_unique<CheckedLibraries>();
  auto nativeConfiguration = configuration;
  nativeConfiguration.features.clear();
  LibraryCacheConfiguration identity;
  identity.compiler = compilerIdentity();
  identity.target = options.target;
  identity.profile = options.profile;
  identity.cc = options.cc;
  identity.sysroot = options.sysroot;
  identity.checks = options.checks.value_or(options.profile != "release");
  identity.freestanding = options.freestanding;
  identity.debugInfo = options.debugInfo;
  identity.targetFeatures = configuration.targetFeatures;
  identity.sanitizers = options.sanitizers;
  for (auto root : nativeRoots) {
    if (root == "std" && options.freestanding)
      break;
    std::string error;
    identity.identity = std::string(nativePackage) + ":" + std::string(root);
    auto inputs = collectLibraryInputs(
        std::filesystem::path(options.libraryDirectory) / root, identity,
        error);
    if (!inputs) {
      if (options.explain)
        std::cerr << "mettle: checked library interface cache ineligible "
                  << root << ": " << error << "; using source\n";
      break;
    }
    auto unit = std::unique_ptr<CheckedLibrary>(
        new CheckedLibrary(options, store, nativeConfiguration, target));
    unit->root = root;
    unit->numeric = numeric;
    unit->archiveKey = std::move(inputs->key);
    unit->sourceInputs = std::move(inputs->sources);
    if (!result->units.empty()) {
      const auto &dependencies = result->units.back()->sourceInputs;
      unit->sourceInputs.insert(dependencies.begin(), dependencies.end());
    }
    identity.dependencies.emplace(root, unit->archiveKey);
    result->units.push_back(std::move(unit));
  }
  return result;
}

bool CheckedLibraries::mount(resolution::Library &library,
                             Diagnostics &diagnostics,
                             const expansion::SourceAllocator &allocate,
                             std::string &error) {
  auto previousMacros = library.compiledMacros;
  for (const auto &unit : units) {
    if (!unit->mount(library, diagnostics, allocate, error))
      return false;
    auto &entry = library.compiled.back();
    for (auto root : nativeRoots) {
      if (root == unit->name())
        break;
      entry.replaces.emplace_back(root);
    }
    entry.declarations = [this, unit = unit.get(),
                          provide = std::move(entry.declarations)]() {
      if (selected && selected->contains(unit->name()))
        return std::optional(Module{});
      auto header = provide();
      if (header)
        selected = unit;
      return header;
    };
  }
  library.compiledMacros =
      [this, previousMacros](const std::vector<std::string> &path,
                             const std::vector<std::string> &from)
      -> std::optional<expansion::MacroModuleSource> {
    if (path.empty())
      return previousMacros ? previousMacros(path, from) : std::nullopt;
    if (selected && selected->contains(path.front()))
      return selected->macroSource(path);
    for (const auto &unit : units)
      if (unit->name() == path.front())
        return unit->macroSource(path);
    return previousMacros ? previousMacros(path, from) : std::nullopt;
  };
  return true;
}

pipeline::LibraryImporter CheckedLibraries::importer() {
  return [this](const Module &module, const resolution::Resolution &resolution,
                Diagnostics &diagnostics) {
    if (!selected)
      return std::optional(pipeline::ImportedProgram{});
    return selected->importer()(module, resolution, diagnostics);
  };
}

const std::map<std::string, Source> &CheckedLibraries::inputs() const {
  static const std::map<std::string, Source> empty;
  return selected ? selected->inputs() : empty;
}

pipeline::PackageOwners CheckedLibraries::packageOwners() const {
  return selected ? selected->packageOwners() : pipeline::PackageOwners{};
}

std::map<std::string, std::vector<std::string>>
CheckedLibraries::packageSources() const {
  std::map<std::string, std::vector<std::string>> sources;
  if (!selected)
    return sources;
  for (const auto &[revision, scope] : selected->archive.sourceModules)
    if (auto source = selected->archive.sources.source(revision);
        source && !scope.empty() && selected->inputs().contains(source->path))
      sources["native:" + scope.front()].push_back(source->path);
  for (auto &[owner, paths] : sources) {
    (void)owner;
    std::sort(paths.begin(), paths.end());
    paths.erase(std::unique(paths.begin(), paths.end()), paths.end());
  }
  return sources;
}
} // namespace mettle::driver
