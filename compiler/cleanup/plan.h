#pragma once

#include "ir/ir.h"
#include <map>

namespace mettle::cleanup {
struct DropPlace {
  Place place;
  Type type;
  int destructor = -1;
  std::vector<int> fields;
  bool indirect = false;
};
struct Plan {
  std::vector<DropPlace> places;
  std::map<Place, int> indices;
  std::vector<std::vector<int>> scopes;
  std::vector<int> unwind;
};
Plan plan(const ir::Function &function, const TypeStore &types);
} // namespace mettle::cleanup
