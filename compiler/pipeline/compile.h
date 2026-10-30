#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/verified.h"
#include "resolution/load.h"
#include "syntax/ast.h"
#include "types/target.h"
#include <optional>

namespace mettle::pipeline {
std::optional<ir::VerifiedProgram> admit(ir::Program program,
                                         Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram> compile(const Source &source,
                                           Diagnostics &diagnostics);
std::optional<ir::VerifiedProgram>
compile(const std::vector<Source> &sources, Diagnostics &diagnostics,
        const resolution::Library &library = {});
std::optional<ir::VerifiedProgram> compile(Module module,
                                           Diagnostics &diagnostics,
                                           bool requireEntry = true,
                                           TargetFacts target = {});
} // namespace mettle::pipeline
