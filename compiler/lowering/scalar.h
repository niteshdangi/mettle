#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include "semantics/checked.h"

namespace mettle::lowering {
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics);
void opaqueAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database,
                    Diagnostics &diagnostics);
bool witnessSlots(ir::Instruction &instruction, const TypeStore &types,
                  Diagnostics &diagnostics);
} // namespace mettle::lowering
