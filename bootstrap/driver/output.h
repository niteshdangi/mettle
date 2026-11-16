#pragma once

#include "diagnostics/diagnostics.h"
#include "driver/options.h"
#include "ir/verified.h"
#include "packages/store.h"
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace mettle::driver {
class BuildInputs;
struct PackageObject {
  std::string identity, source, key;
  // Set for a reusable library object: the library program to lower on a miss.
  std::function<const ir::VerifiedProgram *()> library{};
};
// One object per checked-library package for a single hosted executable
// without debug info, sanitizers, harness or global assembly. Each holds every
// non-generic body of its package, so its key is that package's archive key.
std::vector<PackageObject> libraryObjects(
    const Options &options, const BuildInputs &inputs,
    const ir::Program &program,
    const std::map<std::string, std::vector<std::string>> &packageSources,
    const std::map<std::string, std::string> &packageKeys,
    const std::function<const ir::VerifiedProgram *()> &library);
bool outputOverwritesSource(const Options &options, const Source &source,
                            const Diagnostics &diagnostics);
// Diagnostics supplies source texts/provenance for debug and panic locations.
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program, const Diagnostics &diagnostics,
         const std::vector<PackageObject> &packageObjects = {},
         packages::Store *store = nullptr);
} // namespace mettle::driver
