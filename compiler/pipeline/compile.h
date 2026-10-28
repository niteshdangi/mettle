#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/verified.h"
#include <optional>

namespace mettle::pipeline {
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics);
} // namespace mettle::pipeline
