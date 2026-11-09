#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
void initialization(const ir::Program &program, Diagnostics &diagnostics);
} // namespace mettle::analysis
