#pragma once

#include "types/type.h"

namespace mettle::backend {
std::optional<NumericConstant>
evaluateNumeric(std::string_view operation, Type owner,
                std::span<const NumericConstant> arguments);
} // namespace mettle::backend
