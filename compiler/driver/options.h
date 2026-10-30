#pragma once

#include <cstdint>
#include <optional>
#include <set>
#include <string>
#include <vector>

namespace mettle::driver {
struct Options {
  Options();
  std::string command, input, output, emit = "executable", profile = "debug";
  std::string target, cc, sysroot, libraryDirectory;
  std::optional<bool> checks;
  bool freestanding = false;
  // Package builds (the input is a package directory or its Mettle.toml).
  std::string bin;
  // Requested features: a package's solver input, or for a single source
  // file the features that `@cfg(feature = "...")` tests.
  std::vector<std::string> features, registries;
  bool defaultFeatures = true, locked = false, offline = false;
  bool packageOptions = false;
  // Build cache (see docs/performance.md section 5.1.1). An empty directory
  // selects METTLE_CACHE_DIR, then the user cache directory.
  std::string cacheDir;
  std::uint64_t cacheLimitKib = 512 * 1024, cacheMaxAgeDays = 30;
  bool noCache = false, explain = false, dryRun = false;
  // Link libraries requested by build scripts.
  std::vector<std::string> extraLibraries;
};
std::optional<Options> options(int argc, char **argv);
void usage();
int run(const Options &options);
} // namespace mettle::driver
