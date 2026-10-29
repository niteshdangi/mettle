#include "places/place.h"
#include "types/layout.h"
#include <algorithm>

namespace mettle {
bool alignedPlace(const TypeStore &types, Type root,
                  std::span<const Projection> fields) {
  auto initial = objectLayout(types, root);
  std::optional<std::uint64_t> base =
      initial ? std::optional(initial->alignment) : std::nullopt;
  std::uint64_t offset = 0;
  bool proper = true;
  for (auto projection : fields) {
    if (projection.kind == Projection::Kind::Dereference) {
      if (!types.isView(root) && !types.isPointer(root))
        return false;
      root = types.view(root).payload;
      auto layout = objectLayout(types, root);
      base = layout ? std::optional(layout->alignment) : std::nullopt;
      offset = 0;
      proper = true;
      continue;
    }
    if (projection.kind == Projection::Kind::Slice) {
      if (!types.isProduct(root))
        return false;
      auto element = objectLayout(types, types.product(root).components[0]);
      if (base && element)
        offset += projection.index * element->size;
      root = projection.type;
      continue;
    }
    if (projection.kind != Projection::Kind::Field || !types.isProduct(root))
      return false;
    const auto &record = types.product(root);
    if (projection.index >= record.fields.size())
      return false;
    auto owner = objectLayout(types, root);
    auto field = record.fields[projection.index].type;
    auto target = objectLayout(types, field);
    if (base && owner) {
      offset += owner->fields[projection.index];
      auto alignment = offset ? std::min(*base, offset & (~offset + 1)) : *base;
      proper = target ? alignment >= target->alignment
                      : proper && !record.layout.packing;
    } else {
      proper = (proper && !record.layout.packing) ||
               (target && target->alignment == 1) ||
               (proper && target && target->alignment <= record.layout.packing);
      base = proper && target ? std::optional(target->alignment) : std::nullopt;
      offset = 0;
    }
    root = field;
  }
  return proper;
}
std::optional<Type> projectedType(const TypeStore &types, Type root,
                                  std::span<const Projection> fields) {
  if (!types.contains(root))
    return std::nullopt;
  for (auto projection : fields) {
    if (projection.kind == Projection::Kind::Opaque) {
      if (!types.contains(projection.type))
        return std::nullopt;
      root = projection.type;
      continue;
    }
    if (projection.kind != Projection::Kind::Field &&
        projection.kind != Projection::Kind::Dereference &&
        projection.kind != Projection::Kind::Slice)
      return std::nullopt;
    if (projection.kind == Projection::Kind::Slice) {
      if (!types.isProduct(root) ||
          types.product(root).kind != AggregateKind::Array ||
          !types.isProduct(projection.type) ||
          types.product(projection.type).kind != AggregateKind::Array ||
          types.product(root).components !=
              types.product(projection.type).components ||
          types.product(projection.type).fields.size() != projection.count ||
          projection.index > types.product(root).fields.size() ||
          projection.count >
              types.product(root).fields.size() - projection.index)
        return std::nullopt;
      root = projection.type;
      continue;
    }
    if (projection.kind == Projection::Kind::Dereference) {
      if (!types.isView(root) && !types.isPointer(root))
        return std::nullopt;
      root = types.view(root).payload;
      continue;
    }
    if (projection.type != Type::Unknown &&
        projection.kind == Projection::Kind::Field &&
        (types.isSlice(root) ||
         (types.isProduct(root) &&
          types.product(root).kind == AggregateKind::Array))) {
      auto element = types.isSlice(root) ? types.slice(root).element
                                         : types.product(root).components[0];
      if (projection.type != element)
        return std::nullopt;
      root = element;
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
  for (std::size_t i = 0; i < length; ++i) {
    const auto &a = first.fields[i], &b = second.fields[i];
    if (a.kind == Projection::Kind::Opaque ||
        b.kind == Projection::Kind::Opaque)
      return true;
    if (a == b)
      continue;
    if (a.kind == Projection::Kind::Slice ||
        b.kind == Projection::Kind::Slice) {
      auto end = [](Projection p) {
        return static_cast<std::uint64_t>(p.index) +
               (p.kind == Projection::Kind::Slice ? p.count : 1);
      };
      return a.index < end(b) && b.index < end(a);
    }
    return false;
  }
  return true;
}
bool overlaps(const TypeStore &types, Type root, const Place &first,
              const Place &second) {
  if (first.root != second.root)
    return false;
  for (std::size_t i = 0;
       i < std::min(first.fields.size(), second.fields.size()); ++i)
    if (first.fields[i] != second.fields[i]) {
      auto owner = projectedType(types, root, std::span(first.fields).first(i));
      if (owner && types.isProduct(*owner) &&
          types.product(*owner).layout.unionType)
        return true;
      break;
    }
  return overlaps(first, second);
}
void project(Place &place, Projection projection) {
  if (projection.kind == Projection::Kind::Opaque) {
    auto prior = std::find_if(place.fields.begin(), place.fields.end(),
                              [](const auto &field) {
                                return field.kind == Projection::Kind::Opaque;
                              });
    place.fields.erase(prior, place.fields.end());
  }
  if (!place.fields.empty() &&
      place.fields.back().kind == Projection::Kind::Slice &&
      (projection.kind == Projection::Kind::Field ||
       projection.kind == Projection::Kind::Slice)) {
    projection.index += place.fields.back().index;
    place.fields.pop_back();
  }
  place.fields.push_back(projection);
}
bool containsPlace(const Place &parent, const Place &child) {
  if (parent.root != child.root || parent.fields.size() > child.fields.size())
    return false;
  for (std::size_t i = 0; i < parent.fields.size(); ++i) {
    auto a = parent.fields[i], b = child.fields[i];
    if (a.kind == Projection::Kind::Opaque ||
        b.kind == Projection::Kind::Opaque)
      return false;
    if (a == b)
      continue;
    if (a.kind != Projection::Kind::Slice ||
        b.kind == Projection::Kind::Dereference)
      return false;
    auto width = b.kind == Projection::Kind::Slice ? b.count : 1;
    if (b.index < a.index || width > a.count ||
        b.index - a.index > a.count - width)
      return false;
  }
  return true;
}
bool imprecise(const Place &place) {
  return std::any_of(place.fields.begin(), place.fields.end(),
                     [](const auto &projection) {
                       return projection.kind == Projection::Kind::Opaque;
                     });
}
bool analysisOnly(const Place &place) {
  return imprecise(place) ||
         std::any_of(place.fields.begin(), place.fields.end(),
                     [](const auto &projection) {
                       return projection.kind == Projection::Kind::Field &&
                              projection.type != Type::Unknown;
                     });
}
} // namespace mettle
