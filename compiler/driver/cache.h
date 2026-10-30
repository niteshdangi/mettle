#pragma once

#include "driver/options.h"
#include "packages/store.h"
#include "resolution/load.h"
#include "source/source.h"
#include <map>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace mettle::driver {
// The store the options select (`--cache-dir`, METTLE_CACHE_DIR, the user
// cache directory), or none when caching is off or no directory is known.
std::optional<packages::Store> openStore(const Options &options);

// Identity of the running compiler and runtime library: version, target and
// the size and modification time of both files. Any rebuilt compiler or
// runtime changes every key.
std::string compilerIdentity();

// Every input a build's output depends on, gathered while the sources load.
// User sources count by their token stream, so edits to comments and layout
// reuse the cached output (sound only while no source position reaches the
// output: emitting debug info or panic locations must key positions too);
// library sources count by content; a probed path that does not exist counts as
// absent so creating it invalidates the build.
class BuildInputs {
public:
  explicit BuildInputs(const std::string &libraryDirectory);
  void record(const Source &source);
  void absent(const std::string &path);
  // Generated text that is not a source file (a procedural macro's output)
  // counts by content under `name`.
  void generated(const std::string &name, const std::string &text);
  // The build key: lowercase SHA-256 over the inputs, the root source path
  // (embedded in the object), the output-affecting options including the
  // output's file name (embedded by the linker) and the mounts.
  std::string key(const Options &options,
                  const std::vector<resolution::Library::Package> &mounts,
                  const std::set<std::string> &rootFeatures) const;

private:
  std::string libraryPrefix;
  std::map<std::string, std::string> inputs;
};
} // namespace mettle::driver
