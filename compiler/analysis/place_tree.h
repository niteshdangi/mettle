#pragma once

#include "ir/ir.h"
#include <map>

namespace mettle::analysis {
class PlaceTree {
public:
  PlaceTree(const ir::Function &function, const TypeStore &types);
  std::size_t size() const { return entries.size(); }
  int index(const Place &place) const { return indices.at(place); }
  void set(std::vector<bool> &state, int index, bool value) const;
  bool all(const std::vector<bool> &state, int index) const;
  bool any(const std::vector<bool> &state, int index) const;
  std::string name(int index) const;

private:
  struct Entry {
    Place place;
    std::vector<int> children;
    std::size_t totalFields = 0, first = 0, last = 0;
  };
  const ir::Function &function;
  const TypeStore &types;
  std::map<Place, int> indices;
  std::vector<Entry> entries;
  std::vector<int> order;
  int add(const Place &place);
  void linearize(int index);
};
} // namespace mettle::analysis
