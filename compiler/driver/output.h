#pragma once

#include "driver/options.h"
#include "ir/verified.h"

namespace mettle::driver {
// `sources` are all loaded sources, for the line tables of `-g` builds.
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program, const std::vector<Source> &sources);
}
