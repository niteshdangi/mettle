#pragma once

#include "driver/options.h"
#include "packages/store.h"
#include "resolution/load.h"
#include "source/source.h"
#include <functional>
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace mettle::driver {
// The store the options select (`--cache-dir`, METTLE_CACHE_DIR, the user
// cache directory), or none when caching is off or no directory is known.
std::optional<packages::Store> openStore(const Options &options);

// Linker identity (or content hash) of the compiler and runtime content hashes.
std::string compilerIdentity();
void resetRuntimeIdentity();

// Every input a build's output depends on, gathered while the sources load.
// User sources count by their token stream, so edits to comments and layout
// reuse the cached output (sound only while no source position reaches the
// output: emitting debug info or panic locations must key positions too);
// library sources count by content; a probed path that does not exist counts as
// absent so creating it invalidates the build; a file a source-inclusion macro
// reads counts by content.
struct LibraryInputs;
struct BuildReplay;
class BuildInputs {
public:
  explicit BuildInputs(const std::string &libraryDirectory);
  // `requested` is the path the source was resolved from, when it differs.
  void record(const Source &source, const std::string &requested = {});
  void record(const LibraryInputs &snapshot);
  void include(const Source &source);
  void recordShippedLibrary(const std::string &name, const std::string &key);
  void absent(const std::string &path);
  // Records and returns the environment variable `name`.
  std::optional<std::string> environment(const std::string &name);
  // Generated text that is not a source file (a procedural macro's output)
  // counts by content under `name`.
  void generated(const std::string &name, const std::string &text);
  // The build key: lowercase SHA-256 over the inputs, the root source path
  // (embedded in the object), the output-affecting options including the
  // output's file name (embedded by the linker) and the mounts.
  std::string key(const Options &options,
                  const std::vector<resolution::Library::Package> &mounts,
                  const std::set<std::string> &rootFeatures) const;
  // The probes that produced build `key` from these inputs, replayable
  // without loading the program, or none when an input is not reproducible
  // that way. `checked` names the shipped library `key` also covers.
  std::optional<std::string> trace(const std::string &key,
                                   const std::string &checked) const;
  // Repeats a trace's probes against the current files and environment;
  // `shipped` yields a shipped library's current key. Fails when a probe
  // resolves differently.
  static std::optional<BuildReplay>
  replay(const std::string &libraryDirectory, std::string_view trace,
         const std::function<std::optional<std::string>(const std::string &)>
             &shipped);
  std::vector<std::string> paths() const;
  // A package object key excludes root sources but includes exact package and
  // library source bytes plus the package's resolved dependency object keys.
  std::optional<std::string> packageObjectKey(
      const std::string &identity, const std::vector<std::string> &sources,
      const std::vector<std::pair<std::string, std::string>> &dependencies,
      const std::set<std::string> &features, const Options &options) const;
  bool packageObjectsSafe() const { return packageInputsSafe; }

private:
  void recordDigest(const Source &source, std::string contentDigest);
  std::string libraryPrefix;
  std::map<std::string, std::string> inputs;
  std::map<std::string, std::string> sourceDigests;
  std::set<std::string> absentPaths;
  std::map<std::string, std::set<std::string>> requests;
  std::set<std::string> exactPaths, environmentNames, shippedNames;
  bool packageInputsSafe = true, traceable = true;
};

struct BuildReplay {
  BuildInputs inputs;
  // The traced build key and the key of the shipped library it covers.
  std::string key, checked;
};
} // namespace mettle::driver
