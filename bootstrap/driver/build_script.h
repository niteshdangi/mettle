#pragma once

#include "driver/options.h"
#include "packages/plan.h"
#include "packages/store.h"
#include "resolution/load.h"
#include <map>
#include <set>
#include <string>
#include <vector>

namespace mettle::driver {
// What the build scripts of a package graph contribute to the compile.
struct ScriptResults {
  struct Host {
    std::vector<resolution::Library::Package> modules;
    std::vector<std::string> libraries;
  };
  // Generated sources mounted as root modules.
  std::vector<resolution::Library::Package> modules;
  // Extra `@cfg(feature = ...)` values by package-instance identity.
  std::map<std::string, std::set<std::string>> features;
  std::vector<std::string> libraries;
  std::map<std::string, Host> hosts;
};

void injectHostContext(Options &host,
                       const std::vector<packages::Mount> &mounts,
                       const ScriptResults &results);

// Compiles each script for the host and runs it in its package directory.
// A script's stdout lines `mettle:KEY=VALUE` declare its results:
//   rerun-if-changed=PATH   file or directory (relative to the package)
//   rerun-if-env-changed=VAR
//   reproducible            the output is a function of the declared inputs
//   module=NAME=FILE        mount FILE (relative to the out directory) as
//                           the root module NAME
//   feature=NAME            enable `@cfg(feature = "NAME")` for the package
//   link-lib=NAME           link -lNAME
// The out directory is `target/mettle/out` in the package, also passed as
// METTLE_OUT_DIR. A script is rerun on every build unless it declares
// `reproducible` and every declared input, its binary and its outputs are
// unchanged; undeclared inputs therefore always cause a rerun. Reports
// `build` diagnostics to stderr and returns false on failure. `store` may be
// null (no reuse).
bool runBuildScripts(const Options &options, const packages::Plan &plan,
                     packages::Store *store, ScriptResults &results);
} // namespace mettle::driver
