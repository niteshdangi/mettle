#pragma once

#include "driver/library_archive.h"
#include "driver/library_cache.h"
#include "driver/options.h"
#include "expansion/macros.h"
#include "packages/store.h"
#include "pipeline/compile.h"
#include "semantics/library.h"
#include <memory>

namespace mettle::driver {
class CheckedLibrary {
public:
  static std::unique_ptr<CheckedLibrary>
  native(const std::string &root, const Options &options,
         const expansion::Configuration &configuration, packages::Store &store,
         TargetFacts target, NumericEvaluator numeric, std::string &error);
  bool mount(resolution::Library &library, Diagnostics &diagnostics,
             const expansion::SourceAllocator &allocate, std::string &error);
  pipeline::LibraryImporter importer();
  const std::string &key() const { return archiveKey; }
  const std::map<std::string, Source> &inputs() const { return sourceInputs; }
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
  bool ensureMounted(std::string &error);
  std::optional<pipeline::ImportedProgram>
  import(const Module &module, const resolution::Resolution &resolution,
         Diagnostics &diagnostics);
  LibraryArchive archive;
  std::string archiveKey;
  std::map<std::string, Source> sourceInputs;
  packages::Store::Lease lease;
  expansion::Configuration configuration;
  TargetFacts target;
  std::shared_ptr<const expansion::MacroLibrary> macros;
  LibraryHeaderImport header;
  std::vector<std::pair<std::uint32_t, std::uint32_t>> defaults;
  std::size_t functions = 0, statics = 0, interfaces = 0;
  const Options &options;
  packages::Store &store;
  NumericEvaluator numeric = nullptr;
  resolution::Library *receiverLibrary = nullptr;
  Diagnostics *receiverDiagnostics = nullptr;
  expansion::SourceAllocator allocate;
  std::string root;
  bool mounted = false, used = false, unavailable = false;
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
  const std::map<std::string, Source> &inputs() const;
  pipeline::PackageOwners packageOwners() const;
  std::map<std::string, std::vector<std::string>> packageSources() const;

private:
  std::vector<std::unique_ptr<CheckedLibrary>> units;
  CheckedLibrary *selected = nullptr;
};
} // namespace mettle::driver
