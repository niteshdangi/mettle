#pragma once

#include "diagnostics/diagnostics.h"
#include "semantics/checked.h"
#include <optional>

namespace mettle {
std::optional<CheckedModule> check(Module module, Diagnostics &diagnostics);
} // namespace mettle
