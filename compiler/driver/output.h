#pragma once

#include "driver/options.h"
#include "ir/verified.h"

namespace mettle::driver {
int emit(const Options &options, const Source &source,
         const ir::VerifiedProgram &program);
}
