#pragma once

#include "ir/ir.h"

namespace mettle::ir {
struct Dominance {
  std::vector<std::vector<int>> predecessors;
  std::vector<int> rank, immediate;
  explicit Dominance(const Function &function);
  bool reachable(int block) const { return rank[block] >= 0; }
  bool dominates(int definition, int use) const;

private:
  std::vector<int> entry, end;
};
} // namespace mettle::ir
