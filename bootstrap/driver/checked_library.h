#pragma once

#include "driver/library_archive.h"
#include "driver/library_cache.h"
#include "driver/options.h"
#include "expansion/macros.h"
#include "metadata/type_graph.h"
#include "packages/store.h"
#include "pipeline/compile.h"
#include "semantics/library.h"
#include <future>
#include <map>
#include <memory>

namespace mettle::driver {
class BuildInputs;
class LibraryQueries {
public:
  LibraryInputSnapshots snapshots;
  std::optional<LibraryArchive> findArchive(const std::string &unit,
                                            const std::string &key,
                                            std::string &content) const;
  void publishArchive(std::string unit, std::string key, std::string content,
                      LibraryArchive archive);
  std::shared_ptr<const LibraryHeaderImport>
  findHeader(const std::string &unit, const std::string &content,
             std::span<const SourceId> sources) const;
  void publishHeader(std::string unit, std::string content,
                     std::vector<SourceId> sources,
                     std::shared_ptr<const LibraryHeaderImport> header);
  std::optional<pipeline::ImportedProgram>
  find(const std::string &unit, const std::string &identity) const;
  void publish(std::string unit, std::string identity,
               pipeline::ImportedProgram program);
  std::size_t hits() const { return reused; }

private:
  struct ArchiveEntry {
    std::string key, content;
    LibraryArchive archive;
  };
  struct Entry {
    std::string identity;
    pipeline::ImportedProgram program;
  };
  struct HeaderEntry {
    std::string content;
    std::vector<SourceId> sources;
    std::shared_ptr<const LibraryHeaderImport> header;
  };
  std::map<std::string, Entry> imports;
  std::map<std::string, ArchiveEntry> archives;
  std::map<std::string, HeaderEntry> headers;
  mutable std::size_t reused = 0;
};

class CheckedLibrary {
public:
  bool mount(resolution::Library &library, Diagnostics &diagnostics,
             const expansion::SourceAllocator &allocate, std::string &error);
  pipeline::LibraryImporter importer();
  const std::string &key() const { return archiveKey; }
  pipeline::PackageOwners packageOwners() const;
  std::string sourcePath() const;
  bool active() const { return used; }
  const std::string &name() const { return root; }
  bool contains(std::string_view name) const;
  std::optional<expansion::MacroModuleSource>
  macroSource(const std::vector<std::string> &path);

private:
  friend class CheckedLibraries;
  CheckedLibrary(const Options &options, packages::Store &store,
                 expansion::Configuration configuration, TargetFacts target);
  bool prepareArchive(std::string &error);
  bool loadArchive(std::string &error, bool shipped = false);
  bool publishShippedSelector(std::string &error);
  bool prepareInputs(std::string &error);
  bool collectInputs(std::string &error);
  bool completeInputs(std::string &error);
  bool hasInput(const std::string &path);
  bool loadShipped(std::string &error);
  std::optional<resolution::BuiltinMethodIndex> builtinMethodIndex();
  const Source *input(const std::string &path);
  bool ensureMounted(std::string &error);
  std::optional<pipeline::ImportedProgram>
  import(const Module &module, const resolution::Resolution &resolution,
         Diagnostics &diagnostics);
  struct ImportedTypes {
    std::shared_ptr<TypeStore> types;
    std::shared_ptr<metadata::TypeGraphSymbols> symbols;
    metadata::TypeGraphImport graph;
  };
  ImportedTypes importTypes() const;
  LibraryArchive archive;
  std::future<ImportedTypes> pendingTypes;
  std::string archiveKey;
  std::string archiveContent;
  std::shared_ptr<const LibraryInputs> sourceInputs;
  LibraryCacheConfiguration cacheConfiguration;
  CheckedLibrary *dependency = nullptr;
  packages::Store::Lease lease;
  expansion::Configuration configuration;
  TargetFacts target;
  std::shared_ptr<const expansion::MacroLibrary> macros;
  std::map<std::string, std::optional<SourceId>, std::less<>> macroSources;
  LibraryHeaderImport header;
  std::size_t functions = 0, statics = 0, interfaces = 0;
  const Options &options;
  packages::Store &store;
  NumericEvaluator numeric = nullptr;
  resolution::Library *receiverLibrary = nullptr;
  Diagnostics *receiverDiagnostics = nullptr;
  expansion::SourceAllocator allocate;
  std::string root;
  bool partialInputs = false;
  bool inputsPrepared = false, ineligible = false, mounted = false,
       used = false, unavailable = false, methodIndexUsed = false,
       shippedArchive = false, shippedLoaded = false;
};

class CheckedLibraries {
public:
  static std::unique_ptr<CheckedLibraries>
  create(const Options &options, const expansion::Configuration &configuration,
         packages::Store &store, TargetFacts target, NumericEvaluator numeric);
  bool mount(resolution::Library &library, Diagnostics &diagnostics,
             const expansion::SourceAllocator &allocate, std::string &error);
  pipeline::LibraryImporter importer();
  bool active() const { return selected != nullptr; }
  const std::string &key() const { return selected->key(); }
  const std::string &name() const { return selected->name(); }
  bool containsInput(const std::string &path) const;
  void recordInputs(BuildInputs &inputs) const;
  // The archive keys the shipped selectors name for the native roots, without
  // loading the archives.
  std::map<std::string, std::string> shippedKeys() const;
  pipeline::PackageOwners packageOwners() const;
  std::map<std::string, std::vector<std::string>> packageSources() const;
  std::map<std::string, std::string> packageKeys() const;
  void releaseLeases();

private:
  std::vector<std::unique_ptr<CheckedLibrary>> units;
  CheckedLibrary *selected = nullptr;
};
} // namespace mettle::driver
