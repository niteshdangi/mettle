#pragma once

#include "analysis/origins.h"
#include "diagnostics/diagnostics.h"
#include "ir/ir.h"

namespace mettle::analysis {
struct LoanResults {
  std::vector<FunctionEffects> effects;
  std::size_t reusedFunctions = 0;
};
LoanResults loans(const ir::Program &program, Diagnostics &diagnostics,
                  const ir::Program *prepared = nullptr,
                  const LoanResults *previous = nullptr);
} // namespace mettle::analysis
