#pragma once

#include "ir/ir.h"

namespace mettle::instances {
ir::Function callableAdapter(Type receiver, Type contract, int callee,
                             const TypeStore &types, std::string name);
ir::Function callableContract(Type type, const TypeStore &types);
} // namespace mettle::instances
