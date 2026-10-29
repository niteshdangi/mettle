#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::ir {
bool verifyTarget(const Program &program, Diagnostics &diagnostics);
}
