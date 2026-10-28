#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include "semantics/checked.h"

namespace mettle::lowering {
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics);
} // namespace mettle::lowering
