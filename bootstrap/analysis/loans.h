#pragma once

#include "analysis/origins.h"
#include "diagnostics/diagnostics.h"
#include "ir/ir.h"
#include <functional>
#include <optional>

namespace mettle::analysis {
struct LoanResults {
  std::vector<EffectSummaries::Shared> effects;
  // Which functions' effects were computed; trusted library bodies nothing
  // calls are left out and must be analysed if a later program needs them.
  std::vector<bool> analyzed;
  std::size_t reusedFunctions = 0;
};
LoanResults loans(const ir::Program &program, Diagnostics &diagnostics,
                  const ir::Program *prepared = nullptr,
                  const LoanResults *previous = nullptr,
                  // Unchanged bodies whose analysis has already succeeded:
                  // they are summarized only when something else calls them.
                  const std::vector<bool> *trusted = nullptr,
                  // Supplies the CFG of a trusted function whose body is
                  // deferred, so its summary reflects the body.
                  const std::function<std::optional<ir::Function>(std::size_t)>
                      &loadBody = {},
                  const std::vector<std::size_t> *seeds = nullptr,
                  // Final summaries persisted for trusted functions.
                  const EffectSummaries::Loader &loadEffects = {});
} // namespace mettle::analysis
