#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include "semantics/checked.h"

namespace mettle::lowering {
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics);
void opaqueAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database,
                    Diagnostics &diagnostics);
// One dispatching function per erasable method of each `any` type in the
// program, selected when a generic `T: unsized + I` is instantiated with it.
void erasedAdapters(ir::Program &program, TypeStore &types,
                    const interfaces::Database &database);
bool witnessSlots(ir::Instruction &instruction, const TypeStore &types,
                  Diagnostics &diagnostics);
} // namespace mettle::lowering
