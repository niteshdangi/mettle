#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
void loans(const ir::Program &program, Diagnostics &diagnostics);
}
