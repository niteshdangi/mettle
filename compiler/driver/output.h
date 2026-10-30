#pragma once

#include "diagnostics/diagnostics.h"
#include "driver/options.h"
#include "ir/verified.h"

namespace mettle::driver {
// Diagnostics supplies source texts and generation provenance for `-g`.
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program,
         const Diagnostics &diagnostics);
} // namespace mettle::driver
