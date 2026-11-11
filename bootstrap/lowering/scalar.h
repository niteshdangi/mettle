#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include "semantics/checked.h"
#include <map>

namespace mettle::lowering {
struct ImportedBodies {
  std::map<std::size_t, ir::Function> functions;
  std::map<std::pair<std::size_t, std::size_t>, ir::Function> defaults;
  std::vector<ir::Function> support;
  std::vector<int> closureFunctions;
};
ir::Program lower(const CheckedModule &module, Diagnostics &diagnostics,
                  const ImportedBodies *imported = nullptr);
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
