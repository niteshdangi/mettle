#include "places/place.h"
#include <algorithm>

namespace mettle {
std::optional<Type> projectedType(const TypeStore &types, Type root,
                                  std::span<const Projection> fields) {
  if (!types.contains(root))
    return std::nullopt;
  for (auto projection : fields) {
    if (projection.kind == Projection::Kind::Dereference) {
      if (!types.isView(root))
        return std::nullopt;
      root = types.view(root).payload;
      continue;
    }
    if (!types.isProduct(root))
      return std::nullopt;
    const auto &product = types.product(root);
    if (projection.index >= product.fields.size())
      return std::nullopt;
    root = product.fields[projection.index].type;
    if (!types.contains(root))
      return std::nullopt;
  }
  return root;
}
bool overlaps(const Place &first, const Place &second) {
  if (first.root != second.root)
    return false;
  auto length = std::min(first.fields.size(), second.fields.size());
  return std::equal(first.fields.begin(), first.fields.begin() + length,
                    second.fields.begin());
}
} // namespace mettle
