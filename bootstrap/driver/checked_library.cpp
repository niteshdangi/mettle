#include "driver/checked_library.h"
#include "driver/cache.h"
#include "ir/codec.h"
#include "lowering/scalar.h"
#include "metadata/type_graph.h"
#include "packages/data.h"
#include "packages/sha256.h"
#include "resolution/resolve.h"
#include "support/limits.h"
#include <algorithm>
#include <array>
#include <atomic>
#include <charconv>
#include <future>
#include <iostream>
#include <limits>
#include <set>
#include <sstream>

namespace mettle::driver {
namespace {
using Symbol = std::pair<metadata::SymbolKind, std::uint32_t>;
struct ImportedStorage {
  LibrarySources sources;
  Section ir, declarations;
  ir::FunctionBodyVerifier verifyIRBody, verifyDeclarationPayload;
  std::shared_ptr<const void> backing;
};
constexpr std::string_view nativePackage = "native:standard-library";
constexpr std::array<std::string_view, 3> nativeRoots{"core", "alloc", "std"};

std::string macroRevision(const Source &source, const std::string &directory) {
  std::error_code error;
  auto root = std::filesystem::absolute(directory, error).lexically_normal();
  if (error)
    return {};
  auto path = std::filesystem::path(source.path)
                  .lexically_relative(root)
                  .generic_string();
  if (path.empty())
    return {};
  packages::Sha256 hash;
  for (std::string_view part :
       {nativePackage, std::string_view(path), std::string_view(source.text)}) {
    std::array<char, 4> size;
    for (unsigned i = 0; i < size.size(); ++i)
      size[i] = static_cast<char>(part.size() >> (8 * i));
    hash.update({size.data(), size.size()});
    hash.update(part);
  }
  return hash.finish();
}

const Source *macroSnapshot(const LibrarySources &sources,
                            const expansion::MacroSource &reference,
                            const std::string &directory) {
  for (const auto &source : sources.snapshots())
    if (source.path == reference.path &&
        source.text.size() == reference.bytes &&
        macroRevision(source, directory) == reference.identity)
      return &source;
  return nullptr;
}

std::string definitionSymbol(metadata::SymbolKind kind,
                             const std::string &definition) {
  return std::string(nativePackage) + ":" +
         std::to_string(static_cast<unsigned>(kind)) + ":" + definition;
}

std::string supportPrefix(std::string_view root, std::string_view key) {
  return std::string(nativePackage) + ":" + std::string(root) + ":" +
         std::string(key) + ":support:";
}

std::optional<resolution::BuiltinMethodIndex>
decodeMethodIndex(std::string bytes) {
  Diagnostics diagnostics;
  auto decoded = packages::data::parse(
      {"<builtin-method-index>", std::move(bytes)}, diagnostics, "metadata");
  if (!decoded || decoded->kind != packages::data::Value::Kind::Object)
    return std::nullopt;
  resolution::BuiltinMethodIndex result;
  for (const auto &[module, names] : decoded->object) {
    if ((module != "option" && module != "outcome" && module != "slice" &&
         module != "iter") ||
        names.kind != packages::data::Value::Kind::Array)
      return std::nullopt;
    for (const auto &name : names.array) {
      if (name.kind != packages::data::Value::Kind::String ||
          name.string.empty())
        return std::nullopt;
      result[module].push_back(name.string);
    }
  }
  return result;
}
} // namespace

std::optional<LibraryArchive>
LibraryQueries::findArchive(const std::string &unit, const std::string &key,
                            std::string &content) const {
  auto found = archives.find(unit);
  if (found == archives.end() || found->second.key != key)
    return std::nullopt;
  content = found->second.content;
  return found->second.archive;
}

void LibraryQueries::publishArchive(std::string unit, std::string key,
                                    std::string content,
                                    LibraryArchive archive) {
  archives.insert_or_assign(
      std::move(unit),
      ArchiveEntry{std::move(key), std::move(content), std::move(archive)});
}

std::shared_ptr<const LibraryHeaderImport>
LibraryQueries::findHeader(const std::string &unit, const std::string &content,
                           std::span<const SourceId> sources) const {
  auto found = headers.find(unit);
  if (found == headers.end() || found->second.content != content ||
      !std::equal(sources.begin(), sources.end(), found->second.sources.begin(),
                  found->second.sources.end()))
    return nullptr;
  return found->second.header;
}

void LibraryQueries::publishHeader(
    std::string unit, std::string content, std::vector<SourceId> sources,
    std::shared_ptr<const LibraryHeaderImport> header) {
  headers.insert_or_assign(
      std::move(unit),
      HeaderEntry{std::move(content), std::move(sources), std::move(header)});
}

std::optional<pipeline::ImportedProgram>
LibraryQueries::find(const std::string &unit,
                     const std::string &identity) const {
  auto found = imports.find(unit);
  if (found == imports.end() || found->second.identity != identity)
    return std::nullopt;
  ++reused;
  return found->second.program;
}

void LibraryQueries::publish(std::string unit, std::string identity,
                             pipeline::ImportedProgram program) {
  imports.insert_or_assign(std::move(unit),
                           Entry{std::move(identity), std::move(program)});
}

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
  if (options.libraryQueries)
    if (auto reused = options.libraryQueries->findArchive(root, archiveKey,
                                                          archiveContent)) {
      archive = std::move(*reused);
      if (options.explain)
        std::cerr << "mettle: checked library archive query hit " << root << " "
                  << archiveKey.substr(0, 12) << '\n';
      return true;
    }
  std::optional<LibraryArchive> decoded;
  auto stored = store.mapped(
      archiveKey, limits::sourceBytes,
      [&](const std::shared_ptr<const packages::Store::Mapping> &mapping) {
        const auto bytes = mapping->bytes();
        decoded = decodeLibraryArchive(bytes, archiveKey, error, mapping);
        if (decoded)
          archiveContent = std::string(bytes.substr(bytes.size() - 64));
        return decoded.has_value();
      });
  if (stored.status == packages::Store::Lookup::Hit) {
    archive = std::move(*decoded);
    if (options.libraryQueries)
      options.libraryQueries->publishArchive(root, archiveKey, archiveContent,
                                             archive);
    if (options.explain)
      std::cerr << "mettle: checked library interface cache hit " << root << " "
                << archiveKey.substr(0, 12) << '\n';
    return true;
  }
  if (stored.status == packages::Store::Lookup::Corrupt && options.explain)
    std::cerr << "mettle: checked library interface cache corrupt " << root
              << (error.empty() ? "" : ": " + error) << "; rebuilding\n";
  error.clear();
  LibraryArchive candidate(archiveKey);
  Diagnostics diagnostics;
  expansion::MacroLibrary rules;
  resolution::Library library;
  library.directory = options.libraryDirectory;
  library.freestanding = options.freestanding;
  library.configuration = configuration;
  library.identifyMacroSource = [&](const Source &source) {
    auto revision = candidate.sources.record(source, error);
    return revision ? macroRevision(source, options.libraryDirectory) : "";
  };
  library.macroExports = [&](const expansion::MacroLibrary &source) {
    auto remap = [&](const expansion::MacroSource &reference)
        -> std::optional<SourceId> {
      auto snapshot =
          macroSnapshot(candidate.sources, reference, options.libraryDirectory);
      if (!snapshot)
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
    if (auto source = input(canonical.generic_string()))
      return *source;
    return std::nullopt;
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
      if (!span.source)
        return span;
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
  auto graph = metadata::exportTypeGraph(*program.types, roots, typeSymbols,
                                         metadata::ValidationMode::OnDemand);
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
  archiveContent = encoded->substr(encoded->size() - 64);
  if (!store.putData(archiveKey, *encoded)) {
    error = "cannot publish checked " + root + " interface";
    return false;
  }
  auto snapshot = std::make_shared<const std::string>(std::move(*encoded));
  auto admitted = decodeLibraryArchive(*snapshot, archiveKey, error, snapshot);
  if (!admitted)
    return false;
  archive = std::move(*admitted);
  if (options.libraryQueries)
    options.libraryQueries->publishArchive(root, archiveKey, archiveContent,
                                           archive);
  for (const auto &note : store.prune(archiveKey))
    if (options.explain)
      std::cerr << "mettle: " << note << '\n';
  if (options.explain)
    std::cerr << "mettle: checked library interface cache stored " << root
              << " " << archiveKey.substr(0, 12) << '\n';
  return true;
}

bool CheckedLibrary::prepareInputs(std::string &error) {
  if (inputsPrepared)
    return true;
  if (dependency) {
    if (!dependency->prepareInputs(error))
      return false;
    cacheConfiguration.dependencies =
        dependency->cacheConfiguration.dependencies;
    cacheConfiguration.dependencies.emplace(dependency->root,
                                            dependency->archiveKey);
  }
  auto directory = std::filesystem::path(options.libraryDirectory) / root;
  std::shared_ptr<const LibraryInputs> inputs;
  if (options.libraryQueries) {
    std::string fallback;
    inputs = options.libraryQueries->snapshots.collect(
        directory, cacheConfiguration, error, fallback);
    if (!fallback.empty() && options.explain)
      std::cerr << "mettle: checked library snapshot reuse unavailable " << root
                << ": " << fallback << "; scanning sources\n";
  } else if (auto collected =
                 collectLibraryInputs(directory, cacheConfiguration, error))
    inputs = std::make_shared<const LibraryInputs>(std::move(*collected));
  if (!inputs)
    return false;
  archiveKey = inputs->key;
  sourceInputs = std::move(inputs);
  inputsPrepared = true;
  return true;
}

std::optional<resolution::BuiltinMethodIndex>
CheckedLibrary::builtinMethodIndex() {
  if (ineligible)
    return std::nullopt;
  std::string error;
  if (!prepareInputs(error)) {
    ineligible = true;
    if (options.explain)
      std::cerr << "mettle: builtin method index unavailable: " << error
                << "; using source\n";
    return std::nullopt;
  }
  methodIndexUsed = true;
  packages::Sha256 identity;
  identity.update("mettle.builtin-methods.1:");
  identity.update(archiveKey);
  auto key = identity.finish();
  auto lease = store.acquireLease(key);
  if (!lease) {
    receiverDiagnostics->error("io", {},
                               "cannot acquire builtin method index lease");
    return std::nullopt;
  }
  auto stored = store.data(key, limits::sourceBytes);
  if (stored.status == packages::Store::Lookup::Hit)
    if (auto index = decodeMethodIndex(std::move(stored.bytes))) {
      if (options.explain)
        std::cerr << "mettle: builtin method index cache hit "
                  << key.substr(0, 12) << '\n';
      return index;
    }
  if (stored.status != packages::Store::Lookup::Miss && options.explain)
    std::cerr << "mettle: builtin method index cache corrupt; using source\n";
  auto index = resolution::discoverBuiltinMethods(
      options.libraryDirectory,
      [&](const std::string &path) -> std::optional<Source> {
        std::error_code fileError;
        auto canonical = std::filesystem::weakly_canonical(path, fileError);
        if (fileError) {
          error = "cannot identify " + path + ": " + fileError.message();
          return std::nullopt;
        }
        auto source = input(canonical.generic_string());
        return source ? std::optional(*source) : std::nullopt;
      });
  if (!error.empty()) {
    receiverDiagnostics->error("io", {}, error);
    return std::nullopt;
  }
  std::string encoded = "{";
  for (const auto &[module, names] : index) {
    encoded += packages::data::quote(module) + ":[";
    for (const auto &name : names)
      encoded += packages::data::quote(name) + ",";
    encoded += "],";
  }
  encoded += "}";
  if (!store.putData(key, encoded))
    receiverDiagnostics->error("io", {}, "cannot publish builtin method index");
  return index;
}

const Source *CheckedLibrary::input(const std::string &path) const {
  for (auto unit = this; unit; unit = unit->dependency)
    if (unit->sourceInputs) {
      auto found = unit->sourceInputs->sources.find(path);
      if (found != unit->sourceInputs->sources.end())
        return &found->second;
    }
  return nullptr;
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
  if (root == "core")
    library.builtinMethodIndex = [this] { return builtinMethodIndex(); };
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
    if (path.empty() || path.front() != root || ineligible)
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
    auto snapshot =
        macroSnapshot(archive.sources, source, options.libraryDirectory);
    if (!snapshot)
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
  if (!prepareInputs(error) || !prepareArchive(error)) {
    unavailable = true;
    return false;
  }
  auto &library = *receiverLibrary;
  auto &diagnostics = *receiverDiagnostics;
  // Registers directly and rolls back on failure instead of copying every
  // previously mounted library's sources and generations.
  struct Registration {
    Diagnostics &diagnostics;
    std::size_t sources = diagnostics.registeredSources().size();
    std::size_t generations = diagnostics.registeredGenerations().size();
    bool published = false;
    ~Registration() {
      if (!published)
        diagnostics.discardRegistrations(sources, generations);
    }
  } registration{diagnostics};
  if (!archive.sources.mount(
          diagnostics,
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
  references.sourceRange =
      [&](std::string_view revision) -> std::optional<Span> {
    auto source = archive.sources.source(revision);
    return source ? std::optional(Span{0, source->text.size(), source->id})
                  : std::nullopt;
  };
  std::vector<SourceId> sourceIds;
  for (const auto &source : archive.sources.snapshots())
    sourceIds.push_back(source.id);
  auto retained =
      options.libraryQueries
          ? options.libraryQueries->findHeader(root, archiveContent, sourceIds)
          : nullptr;
  auto decoded = retained
                     ? copyLibraryHeader(*retained)
                     : decodeLibraryHeader(archive.header, references,
                                           archive.header.owner(),
                                           metadata::ValidationMode::OnDemand);
  if (!decoded) {
    error = decoded.error;
    return false;
  }
  if (options.libraryQueries && !retained) {
    retained = std::make_shared<const LibraryHeaderImport>(std::move(decoded));
    options.libraryQueries->publishHeader(root, archiveContent,
                                          std::move(sourceIds), retained);
    decoded = copyLibraryHeader(*retained);
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
    auto snapshot =
        macroSnapshot(archive.sources, source, options.libraryDirectory);
    if (!snapshot) {
      error =
          "compiled macro source revision does not match the library archive";
      return false;
    }
  }
  header = std::move(decoded);
  functions = header.module->functions.size();
  statics = header.module->statics.size();
  interfaces = header.module->interfaces.size();
  macros = std::make_shared<const expansion::MacroLibrary>(std::move(*rules));
  registration.published = true;
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
  if (!archive.verifyIRBody || !archive.verifyDeclarationPayload)
    return fail(
        "compiled library is missing authenticated payload commitments");
  auto catalog = header.index;
  if (!catalog)
    return fail("compiled library declaration directory is absent");
  auto packageIndices =
      std::make_shared<std::map<std::string, std::uint32_t>>();
  auto closureCount = catalog->symbolCount(metadata::SymbolKind::Closure);
  for (std::uint32_t i = 0;
       i < catalog->symbolCount(metadata::SymbolKind::Package); ++i)
    if (auto symbol = catalog->symbol(metadata::SymbolKind::Package, i)) {
      auto destination = resolution.packageIndex(symbol->definition);
      if (!destination)
        return fail("compiled package identity is absent from the consumer");
      packageIndices->emplace(symbol->definition, *destination);
    }
  if (catalog->symbolCount(metadata::SymbolKind::Function) != functions ||
      catalog->symbolCount(metadata::SymbolKind::Static) != statics ||
      catalog->symbolCount(metadata::SymbolKind::Interface) != interfaces)
    return fail("compiled function inventory is incomplete");
  std::map<std::pair<std::uint32_t, std::uint32_t>, std::uint32_t>
      defaultDestinations;
  auto nativeDefaults = catalog->defaultCount();
  std::size_t defaultCount = nativeDefaults;
  for (std::size_t i = module.functions.nativeSize();
       i < module.functions.size(); ++i)
    for (std::size_t j = 0; j < module.functions.header(i).parameters.size();
         ++j) {
      const auto &parameter = module.functions.header(i).parameters[j];
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
  auto supportBase = module.functions.size() + defaultCount;
  auto prefix = supportPrefix(root, archiveKey);
  auto largestSupportOrdinal = std::make_shared<std::atomic<std::int64_t>>(-1);
  auto supportLimit =
      std::make_shared<std::atomic<std::size_t>>(limits::functions);
  metadata::DecodeReferences references;
  references.source = [&](const auto &source) {
    return archive.sources.resolve(source);
  };
  references.symbol =
      [catalog, functionCount = module.functions.size(), packageIndices, prefix,
       supportBase, largestSupportOrdinal,
       supportLimit](metadata::SymbolKind kind,
                     std::string_view name) -> std::optional<std::uint32_t> {
    if (kind == metadata::SymbolKind::Package) {
      auto found = packageIndices->find(std::string(name));
      return found == packageIndices->end() ? std::nullopt
                                            : std::optional{found->second};
    }
    if (auto found = catalog->symbol(kind, name))
      return found;
    if (kind == metadata::SymbolKind::Function) {
      auto delimiter = name.rfind(":default:");
      if (delimiter != std::string_view::npos) {
        auto function = catalog->symbol(kind, name.substr(0, delimiter));
        auto parameterText = name.substr(delimiter + 9);
        std::uint32_t parameter = 0;
        auto parsed = std::from_chars(
            parameterText.data(), parameterText.data() + parameterText.size(),
            parameter);
        if (function && parsed.ec == std::errc{} &&
            parsed.ptr == parameterText.data() + parameterText.size())
          if (auto ordinal = catalog->defaultOrdinal(*function, parameter))
            return static_cast<std::uint32_t>(functionCount + *ordinal);
        return std::nullopt;
      }
    }
    if (kind != metadata::SymbolKind::Function || !name.starts_with(prefix))
      return std::nullopt;
    name.remove_prefix(prefix.size());
    std::uint32_t ordinal = 0;
    auto parsed =
        std::from_chars(name.data(), name.data() + name.size(), ordinal);
    if (parsed.ec != std::errc{} || parsed.ptr != name.data() + name.size() ||
        ordinal >= limits::functions ||
        supportBase + ordinal >= limits::functions ||
        ordinal >= supportLimit->load())
      return std::nullopt;
    auto largest = largestSupportOrdinal->load();
    while (ordinal > largest &&
           !largestSupportOrdinal->compare_exchange_weak(largest, ordinal)) {
    }
    return static_cast<std::uint32_t>(supportBase + ordinal);
  };
  packages::Sha256 identity;
  auto integer = [&](std::uint64_t value) {
    std::array<char, 8> bytes;
    for (unsigned i = 0; i < bytes.size(); ++i)
      bytes[i] = static_cast<char>(value >> (8 * i));
    identity.update({bytes.data(), bytes.size()});
  };
  auto text = [&](std::string_view value) {
    integer(value.size());
    identity.update(value);
  };
  text(archiveKey);
  text(archiveContent);
  integer(archive.sources.snapshots().size());
  for (const auto &source : archive.sources.snapshots())
    integer(source.id);
  integer(supportBase);
  integer(nativeDefaults);
  integer(defaultDestinations.size());
  for (const auto &[parameter, destination] : defaultDestinations) {
    integer(parameter.first);
    integer(parameter.second);
    integer(destination);
  }
  integer(packageIndices->size());
  for (const auto &[package, index] : *packageIndices) {
    text(package);
    integer(index);
  }
  auto queryIdentity = identity.finish();
  if (options.libraryQueries)
    if (auto reused = options.libraryQueries->find(root, queryIdentity))
      return reused;
  auto storage = std::make_shared<const ImportedStorage>(ImportedStorage{
      archive.sources, std::move(archive.ir), archive.declarations,
      archive.verifyIRBody, archive.verifyDeclarationPayload, archive.backing});
  references.source = [storage](const auto &source) {
    return storage->sources.resolve(source);
  };
  auto types = std::make_shared<TypeStore>();
  types->setPointerBits(target.pointerBits);
  types->setVaListAbi(targetVaListAbi(target));
  auto typeSymbols = std::make_shared<metadata::TypeGraphSymbols>();
  typeSymbols->resolve = references.symbol;
  auto graph = metadata::importTypeGraph(*types, archive.types, *typeSymbols,
                                         metadata::ValidationMode::OnDemand,
                                         typeSymbols, archive.types.owner());
  if (!graph)
    return fail(graph.error);
  auto roots = std::make_shared<std::vector<Type>>(std::move(graph.roots));
  references.type = [roots](std::uint32_t reference) -> std::optional<Type> {
    if (reference >= roots->size())
      return std::nullopt;
    return (*roots)[reference];
  };
  auto retainedReferences =
      std::make_shared<const metadata::DecodeReferences>(references);
  auto pendingIR = std::async(
      std::launch::async | std::launch::deferred,
      [storage, retainedReferences] {
        return ir::decodeProgramLazy(
            storage->ir, *retainedReferences, true, retainedReferences, storage,
            storage->verifyIRBody, metadata::ValidationMode::OnDemand);
      });
  auto declarations = importLibraryDeclarations(
      storage->declarations, types, *retainedReferences, &module, storage,
      retainedReferences, metadata::ValidationMode::OnDemand, {},
      storage->verifyDeclarationPayload, catalog);
  if (!declarations)
    return fail(declarations.error);
  if (declarations.declarations->closures.size() != closureCount)
    return fail("compiled closure declarations do not form the header prefix");
  auto decoded = pendingIR.get();
  if (!decoded)
    return fail(decoded.error);
  if (decoded.program.functions.size() < functions + nativeDefaults ||
      decoded.program.statics.size() != statics)
    return fail("compiled IR definitions do not match the declaration header");
  auto supportCount =
      decoded.program.functions.size() - functions - nativeDefaults;
  supportLimit->store(supportCount);
  if (largestSupportOrdinal->load() >= static_cast<std::int64_t>(supportCount))
    return fail("compiled support identity exceeds its artifact-local table");
  auto bodies = std::make_shared<lowering::ImportedBodies>();
  bodies->functionRecords.resize(functions);
  std::size_t sourceBodies = 0;
  std::vector<std::optional<std::size_t>> supportRecords(supportCount);
  for (std::size_t i = 0; i < decoded.program.functions.size(); ++i) {
    auto destination = decoded.functionDestinations[i];
    if (destination < functions) {
      if (bodies->functionRecords[destination])
        return fail("duplicate compiled function destination");
      auto symbol =
          catalog->symbol(metadata::SymbolKind::Function, destination);
      if (!symbol || decoded.functionIdentities[i] != symbol->definition)
        return fail("compiled function identity does not match its header");
      bodies->functionRecords[destination] = i;
      ++sourceBodies;
    } else if (destination < supportBase) {
      if (destination < module.functions.size() ||
          destination - module.functions.size() >= nativeDefaults)
        return fail("compiled body occupies a consumer default-helper slot");
      decoded.program.functionIndex[i].name = decoded.functionIdentities[i];
      if (!bodies->defaultRecords
               .emplace(
                   catalog->defaultAt(destination - module.functions.size()), i)
               .second)
        return fail("duplicate compiled function destination");
    } else if (destination - supportBase < supportCount) {
      decoded.program.functionIndex[i].name = decoded.functionIdentities[i];
      if (supportRecords[destination - supportBase])
        return fail("duplicate compiled function destination");
      supportRecords[destination - supportBase] = i;
    } else {
      return fail("compiled body destination exceeds its support table");
    }
  }
  if (sourceBodies != functions ||
      bodies->defaultRecords.size() != nativeDefaults)
    return fail("compiled IR is missing a source function or default helper");
  for (auto record : supportRecords)
    if (!record)
      return fail("compiled support destinations contain a gap");
  bodies->supportRecords = std::move(supportRecords);
  bodies->headers = std::move(decoded.program.functions);
  bodies->statics = std::move(decoded.program.statics);
  bodies->headerIndex = std::move(decoded.program.functionIndex);
  if (!decoded.lazyFunctions)
    return fail("compiled IR function body loader is absent");
  bodies->functionBodySizes = std::move(decoded.functionBodySizes);
  auto lazyFunctions = decoded.lazyFunctions;
  auto bodyReferences = references;
  bodies->loadFunction =
      [lazyFunctions, bodyReferences = std::move(bodyReferences),
       largestSupportOrdinal, supportCount](
          std::size_t record, const ir::Function &header,
          std::string &error) mutable -> std::optional<ir::Function> {
    auto decodedBody = lazyFunctions->load(record, header, bodyReferences);
    if (!decodedBody) {
      error = std::move(decodedBody.error);
      return std::nullopt;
    }
    if (largestSupportOrdinal->load() >=
        static_cast<std::int64_t>(supportCount)) {
      error = "compiled support identity exceeds its artifact-local table";
      return std::nullopt;
    }
    return std::move(decodedBody.function);
  };
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
  types->shareInterning();
  decoded.program.types = types;
  pipeline::ImportedProgram imported;
  imported.declarations = std::move(declarations.declarations);
  imported.bodies = std::move(bodies);
  imported.metadata = std::move(decoded.program);
  if (options.libraryQueries)
    options.libraryQueries->publish(root, queryIdentity, imported);
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
    identity.identity = std::string(nativePackage) + ":" + std::string(root) +
                        ":macro-provenance-1";
    auto unit = std::unique_ptr<CheckedLibrary>(
        new CheckedLibrary(options, store, nativeConfiguration, target));
    unit->root = root;
    unit->numeric = numeric;
    unit->cacheConfiguration = identity;
    if (!result->units.empty())
      unit->dependency = result->units.back().get();
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
    entry.available = [unit = unit.get()]() {
      if (unit->ineligible)
        return false;
      std::string error;
      if (unit->prepareInputs(error))
        return true;
      unit->ineligible = true;
      if (unit->options.explain)
        std::cerr << "mettle: checked library interface cache ineligible "
                  << unit->root << ": " << error << "; using source\n";
      return false;
    };
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
      if (unit->name() == path.front() && !unit->ineligible)
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

bool CheckedLibraries::containsInput(const std::string &path) const {
  return selected && selected->input(path);
}

void CheckedLibraries::recordInputs(BuildInputs &inputs) const {
  for (auto unit = selected; unit; unit = unit->dependency)
    inputs.record(*unit->sourceInputs);
  if (!selected)
    for (const auto &unit : units)
      if (unit->methodIndexUsed)
        inputs.record(*unit->sourceInputs);
}

pipeline::PackageOwners CheckedLibraries::packageOwners() const {
  return selected ? selected->packageOwners() : pipeline::PackageOwners{};
}

std::map<std::string, std::string> CheckedLibraries::packageKeys() const {
  std::map<std::string, std::string> keys;
  for (const auto &unit : units) {
    if (!selected)
      return keys;
    keys["native:" + unit->root] = unit->archiveKey;
    if (unit.get() == selected)
      break;
  }
  return keys;
}

std::map<std::string, std::vector<std::string>>
CheckedLibraries::packageSources() const {
  std::map<std::string, std::vector<std::string>> sources;
  if (!selected)
    return sources;
  for (const auto &[revision, scope] : selected->archive.sourceModules)
    if (auto source = selected->archive.sources.source(revision);
        source && !scope.empty() && selected->input(source->path))
      sources["native:" + scope.front()].push_back(source->path);
  for (auto &[owner, paths] : sources) {
    (void)owner;
    std::sort(paths.begin(), paths.end());
    paths.erase(std::unique(paths.begin(), paths.end()), paths.end());
  }
  return sources;
}
} // namespace mettle::driver
