#pragma once

#include "diagnostics/diagnostics.h"
#include "driver/options.h"
#include "ir/verified.h"
#include "packages/store.h"
#include <optional>
#include <string>
#include <vector>

namespace mettle::driver {
class BuildInputs;
struct PackageObject {
  std::string identity, source, key;
};
// Single hosted executable, debug/release without debug info, sanitizers,
// harness or global assembly; only root/native-library ownership.
std::optional<PackageObject>
nativePackageObject(const Options &options, const BuildInputs &inputs,
                    const ir::VerifiedProgram &program,
                    const std::string &identity,
                    const std::vector<std::string> &sources,
                    const std::string &checkedKey, std::string &error);
bool outputOverwritesSource(const Options &options, const Source &source,
                            const Diagnostics &diagnostics);
// Diagnostics supplies source texts and generation provenance for `-g`.
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program, const Diagnostics &diagnostics,
         const std::vector<PackageObject> &packageObjects = {},
         packages::Store *store = nullptr);
} // namespace mettle::driver
