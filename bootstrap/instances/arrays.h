#pragma once

#include "ir/ir.h"

namespace mettle::instances {
void expandArrays(ir::Function &function, const TypeStore &types);
} // namespace mettle::instances
