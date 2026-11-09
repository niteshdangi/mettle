#pragma once

#include "driver/options.h"
#include "resolution/load.h"
#include "syntax/ast.h"
#include <map>
#include <string>
#include <vector>

namespace mettle::driver {
// Checks and builds the input per `options` (`check`/`build`, or a build of
// the test/benchmark harness when `options.harness` is set). The selected
// package's annotated functions are returned through `discovered` when given.
int build(const Options &options, std::vector<Module::TestFunction> *discovered,
          std::vector<resolution::SourceModule> *sourceModules = nullptr,
          const std::map<std::string, std::string> *sourceOverrides = nullptr);
// `mettle run`, `mettle test` and `mettle bench`: build into a private
// temporary directory, run the result and report.
int execute(const Options &options);
} // namespace mettle::driver
