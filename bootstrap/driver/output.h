#pragma once

#include "diagnostics/diagnostics.h"
#include "driver/options.h"
#include "ir/verified.h"
#include "packages/store.h"
#include <string>
#include <vector>

namespace mettle::driver {
struct PackageObject {
  std::string identity, source, key;
};
// Diagnostics supplies source texts and generation provenance for `-g`.
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program, const Diagnostics &diagnostics,
         const std::vector<PackageObject> &packageObjects = {},
         packages::Store *store = nullptr);
} // namespace mettle::driver
