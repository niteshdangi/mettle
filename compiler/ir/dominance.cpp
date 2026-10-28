#include "ir/dominance.h"
#include <algorithm>
#include <utility>

namespace mettle::ir {
Dominance::Dominance(const Function &function)
    : predecessors(function.blocks.size()), rank(function.blocks.size(), -1),
      immediate(function.blocks.size(), -1) {
  std::vector<std::vector<int>> successors(function.blocks.size());
  for (std::size_t b = 0; b < function.blocks.size(); ++b) {
    const auto &exit = function.blocks[b].exit;
    if (exit.kind == Exit::Jump || exit.kind == Exit::Branch)
      successors[b].push_back(exit.first);
    if (exit.kind == Exit::Branch && exit.second != exit.first)
      successors[b].push_back(exit.second);
    for (auto target : successors[b])
      predecessors[target].push_back(static_cast<int>(b));
  }
  std::vector<int> order;
  std::vector<bool> visited(function.blocks.size());
  std::vector<std::pair<int, bool>> stack{{0, false}};
  while (!stack.empty()) {
    auto [block, finished] = stack.back();
    stack.pop_back();
    if (finished) {
      order.push_back(block);
      continue;
    }
    if (visited[block])
      continue;
    visited[block] = true;
    stack.emplace_back(block, true);
    for (auto next : successors[block])
      if (!visited[next])
        stack.emplace_back(next, false);
  }
  std::reverse(order.begin(), order.end());
  for (std::size_t i = 0; i < order.size(); ++i)
    rank[order[i]] = static_cast<int>(i);
  immediate[0] = 0;
  auto intersect = [&](int a, int b) {
    while (a != b) {
      while (rank[a] > rank[b])
        a = immediate[a];
      while (rank[b] > rank[a])
        b = immediate[b];
    }
    return a;
  };
  bool changed;
  do {
    changed = false;
    for (auto block : order) {
      if (block == 0)
        continue;
      int parent = -1;
      for (auto predecessor : predecessors[block])
        if (immediate[predecessor] >= 0)
          parent = parent < 0 ? predecessor : intersect(parent, predecessor);
      if (parent != immediate[block]) {
        immediate[block] = parent;
        changed = true;
      }
    }
  } while (changed);
}
bool Dominance::dominates(int definition, int use) const {
  if (!reachable(use))
    return true;
  if (!reachable(definition))
    return false;
  while (rank[use] > rank[definition])
    use = immediate[use];
  return definition == use;
}
} // namespace mettle::ir
