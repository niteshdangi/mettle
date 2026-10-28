#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::ir {
bool verify(const Program &program, Diagnostics &diagnostics);
} // namespace mettle::ir
