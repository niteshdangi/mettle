#pragma once

#include "packages/plan.h"
#include "resolution/load.h"
#include <cstdint>
#include <optional>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace mettle::driver {
struct Options {
  Options();
  // `mettle fmt FILE...` and `mettle doc PATH...`: `input` is the first path,
  // `moreInputs` the rest.
  std::vector<std::string> moreInputs;
  bool check = false;
  std::string command, input, output, emit = "executable", profile = "debug";
  std::string target, cc, sysroot, libraryDirectory;
  std::optional<bool> checks;
  bool freestanding = false;
  // `-g`: source-level DWARF (not implied by any profile, so default output
  // stays byte-identical).
  bool debugInfo = false;
  // Package builds (the input is a package directory or its Mettle.toml).
  std::string bin;
  // Requested features: a package's solver input, or for a single source
  // file the features that `@cfg(feature = "...")` tests.
  std::vector<std::string> features, registries;
  bool defaultFeatures = true, locked = false, offline = false;
  bool packageOptions = false;
  std::set<std::string> sanitizers;
  std::string sanitizerError;
  // Internal package context for host build programs and procedural macros.
  bool packageContext = false;
  std::set<std::string> injectedFeatures;
  std::vector<resolution::Library::Package> injectedPackages;
  std::vector<std::pair<std::string, std::string>> packageDependencies;
  // Build cache (see docs/performance.md section 5.1.1). An empty directory
  // selects METTLE_CACHE_DIR, then the user cache directory.
  std::string cacheDir;
  std::uint64_t cacheLimitKib = 512 * 1024, cacheMaxAgeDays = 30;
  bool noCache = false, explain = false, dryRun = false;
  // Link libraries requested by build scripts.
  std::vector<std::string> extraLibraries;
  // `mettle run`: arguments after `--`. `mettle test`/`bench`: name filters,
  // selection, output format and test timeout. Internally a test or benchmark
  // build selects the harness entry (`test`, `bench`; empty for ordinary
  // builds).
  std::vector<std::string> programArguments, filters;
  bool exact = false, includeIgnored = false, onlyIgnored = false;
  std::string format = "human";
  unsigned jobs = 0;
  std::optional<unsigned> timeoutSeconds;
  // `mettle test --doc` runs only the doctests; `mettle doc --private` also
  // documents items that are not `pub`.
  bool docOnly = false, documentPrivate = false;
  std::string harness;
  // `mettle lint`: (level, rule) from `--allow|--warn|--deny RULE`, in order;
  // the rule `warnings` selects every rule not named otherwise.
  std::vector<std::pair<std::string, std::string>> lintLevels;
};
std::optional<Options> options(int argc, char **argv);
void usage();
int run(const Options &options);
// The package-plan request for `options`, with Git checkouts via system `git`.
packages::Request packageRequest(const Options &options);
} // namespace mettle::driver
