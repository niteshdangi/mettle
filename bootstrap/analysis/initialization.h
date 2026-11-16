#pragma once

#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
void initialization(const ir::Program &program, Diagnostics &diagnostics,
                    const ir::Program *prepared = nullptr,
                    const std::vector<bool> *trusted = nullptr);
} // namespace mettle::analysis
