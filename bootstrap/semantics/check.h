#pragma once

#include "diagnostics/diagnostics.h"
#include "semantics/checked.h"
#include <optional>

namespace mettle {
std::optional<CheckedModule> check(Module module, Diagnostics &diagnostics,
                                   bool requireEntry = true,
                                   TargetFacts target = {},
                                   NumericEvaluator numericEvaluator = nullptr);
std::optional<CheckedModule>
check(Module module, Diagnostics &diagnostics,
      std::shared_ptr<const resolution::Resolution> symbols,
      bool requireEntry = true, TargetFacts target = {},
      NumericEvaluator numericEvaluator = nullptr,
      std::shared_ptr<const ImportedDeclarations> imported = nullptr);
} // namespace mettle
