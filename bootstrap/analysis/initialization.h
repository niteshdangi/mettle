#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
void initialization(const ir::Program &program, Diagnostics &diagnostics,
                    const ir::Program *prepared = nullptr);
} // namespace mettle::analysis
