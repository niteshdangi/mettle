#include "analysis/place_tree.h"
#include <algorithm>

namespace mettle::analysis {
int PlaceTree::index(const Place &place) const {
  if (auto found = indices.find(place); found != indices.end())
    return found->second;
  Place canonical{place.root, {}};
  for (auto projection : place.fields)
    project(canonical, projection);
  if (!canonical.fields.empty() &&
      canonical.fields.back().kind == Projection::Kind::Slice)
    canonical.fields.pop_back();
  return indices.at(canonical);
}
PlaceTree::PlaceTree(const ir::Function &function, const TypeStore &types)
    : function(function), types(types) {
  for (std::size_t i = 0; i < function.locals.size(); ++i)
    add({static_cast<int>(i), {}});
  for (const auto &block : function.blocks)
    for (const auto &instruction : block.instructions)
      if (instruction.op == ir::Op::BorrowRead ||
          instruction.op == ir::Op::VariantTest ||
          instruction.op == ir::Op::BorrowMut ||
          instruction.op == ir::Op::ReserveMut ||
          instruction.op == ir::Op::ViewRead ||
          instruction.op == ir::Op::ArrayBorrowRead ||
          instruction.op == ir::Op::ArrayBorrowMut ||
          instruction.op == ir::Op::ArrayTake ||
          instruction.op == ir::Op::EraseView ||
          instruction.op == ir::Op::ErasedUpcast ||
          instruction.op == ir::Op::UnsizeView ||
          instruction.op == ir::Op::SliceLength ||
          instruction.op == ir::Op::SliceBorrowRead ||
          instruction.op == ir::Op::SliceBorrowMut ||
          instruction.op == ir::Op::ViewMut || instruction.op == ir::Op::Load ||
          instruction.op == ir::Op::Move || instruction.op == ir::Op::Store ||
          instruction.op == ir::Op::StorageWrite ||
          instruction.op == ir::Op::DropPlace ||
          instruction.op == ir::Op::Declare)
        add(instruction.place);
  for (std::size_t i = 0; i < function.locals.size(); ++i)
    linearize(index({static_cast<int>(i), {}}));
}
int PlaceTree::add(const Place &place) {
  if (auto found = indices.find(place); found != indices.end())
    return found->second;
  Place canonical{place.root, {}};
  for (auto projection : place.fields)
    project(canonical, projection);
  if (canonical != place) {
    auto id = add(canonical);
    indices.emplace(place, id);
    return id;
  }
  if (!place.fields.empty() &&
      place.fields.back().kind == Projection::Kind::Slice) {
    auto root = place;
    root.fields.pop_back();
    int id = add(root);
    indices.emplace(place, id);
    return id;
  }
  int parent = -1;
  if (!place.fields.empty()) {
    auto prefix = place;
    prefix.fields.pop_back();
    parent = add(prefix);
  }
  int id = static_cast<int>(entries.size());
  auto type =
      projectedType(types, function.locals.at(place.root).type, place.fields)
          .value();
  std::size_t fields =
      types.isProduct(type) ? types.product(type).fields.size() : 0;
  indices.emplace(place, id);
  entries.push_back({place, {}, fields});
  if (parent >= 0)
    entries[parent].children.push_back(id);
  return id;
}
void PlaceTree::linearize(int index) {
  entries[index].first = order.size();
  order.push_back(index);
  for (auto child : entries[index].children)
    linearize(child);
  entries[index].last = order.size();
}
void PlaceTree::set(std::vector<bool> &state, int index, bool value) const {
  const auto &place = entries[index].place;
  Place prefix{place.root, {}};
  for (auto projection : place.fields) {
    auto owner =
        projectedType(types, function.locals[place.root].type, prefix.fields);
    if (owner && types.isProduct(*owner) &&
        types.product(*owner).layout.unionType) {
      index = this->index(prefix);
      break;
    }
    prefix.fields.push_back(projection);
  }
  for (auto i = entries[index].first; i < entries[index].last; ++i)
    state[order[i]] = value;
}
bool PlaceTree::all(const std::vector<bool> &state, int index) const {
  const auto &entry = entries[index];
  if (entry.totalFields == 0)
    return state[index];
  if (entry.children.size() < entry.totalFields && !state[index])
    return false;
  for (auto child : entry.children)
    if (!all(state, child))
      return false;
  return true;
}
bool PlaceTree::any(const std::vector<bool> &state, int index) const {
  const auto &entry = entries[index];
  if (entry.totalFields == 0)
    return state[index];
  if (entry.children.size() < entry.totalFields && state[index])
    return true;
  for (auto child : entry.children)
    if (any(state, child))
      return true;
  return false;
}
std::string PlaceTree::name(int index) const {
  const auto &place = entries[index].place;
  std::string result = function.locals.at(place.root).name;
  auto type = function.locals.at(place.root).type;
  for (auto field : place.fields) {
    if (field.kind == Projection::Kind::Dereference) {
      result = "*" + result;
      type = types.view(type).payload;
      continue;
    }
    const auto &descriptor = types.product(type).fields.at(field.index);
    result += "." + descriptor.name;
    type = descriptor.type;
  }
  return result;
}
} // namespace mettle::analysis
