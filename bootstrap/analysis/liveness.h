#pragma once

#include "ir/ir.h"
#include <set>
#include <vector>

namespace mettle::analysis {
// SSA values live at block boundaries. Phi operands are uses on the
// corresponding incoming edge, rather than uses in the successor block.
// The input CFG must already have passed structural verification.
struct ValueLiveness {
  std::vector<std::set<int>> in, out;
};
ValueLiveness valueLiveness(const ir::Function &function);
} // namespace mettle::analysis
