#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
void valueOwnership(const ir::Function &function, const TypeStore &types,
                    Diagnostics &diagnostics);
}
