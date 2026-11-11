#pragma once

#include "driver/build_script.h"
#include "driver/cache.h"
#include "driver/options.h"
#include "expansion/procedural.h"
#include "packages/plan.h"
#include "packages/store.h"
#include <map>
#include <string>
#include <vector>

namespace mettle::driver {
// Builds and runs the procedural macro programs of a package graph.
//
// Each program is compiled for the host whatever the build target is. An
// invocation runs it in its package directory with the request (see
// expansion/procedural.h) on standard input and the package identity in
// METTLE_PACKAGE_DIR/NAME/VERSION, METTLE_TARGET, METTLE_PROFILE and
// METTLE_MACRO_API. A result is reused only when the program declared it
// `reproducible` and the program binary, the request, every declared input and
// every declared environment variable are unchanged; undeclared inputs
// therefore always cause a rerun. Within one build an identical invocation
// runs once. Every response text is recorded in `inputs`, so a changed
// expansion changes the build key and an unchanged one reuses the output.
class ProcedureHost {
public:
  // `store` and `inputs` must outlive the host; `store` may be null.
  ProcedureHost(const Options &options, std::vector<packages::Macro> macros,
                std::vector<packages::Mount> hostPackages,
                ScriptResults scriptResults, packages::Store *store,
                BuildInputs &inputs);
  ProcedureHost(const ProcedureHost &) = delete;
  ProcedureHost &operator=(const ProcedureHost &) = delete;

  // Compiles every program. Reports `build` diagnostics to stderr and returns
  // false on failure.
  bool prepare();
  const expansion::Procedures &procedures() const { return available; }

private:
  struct Program {
    packages::Macro macro;
    std::string binary, binaryHash;
  };
  const Options &options;
  std::vector<Program> programs;
  std::vector<packages::Mount> hostPackages;
  ScriptResults scriptResults;
  packages::Store *store;
  BuildInputs &inputs;
  expansion::Procedures available;
  std::map<std::string, expansion::ProcedureResponse> memo;

  expansion::ProcedureResponse invoke(const std::string &name,
                                      const std::string &request);
  expansion::ProcedureResponse execute(const Program &program,
                                       const std::string &request,
                                       const std::string &key);
};
} // namespace mettle::driver
