#include "types/type.h"
#include <limits>
#include <stdexcept>
#include <utility>

namespace mettle {
std::string_view typeName(Type type) {
  if (type == Type::I32)
    return "i32";
  if (type == Type::Bool)
    return "bool";
  if (type == Type::Unit)
    return "Unit";
  if (type == Type::Never)
    return "Never";
  if (type == Type::Unknown)
    return "<unresolved>";
  return "<invalid>";
}
namespace {
constexpr std::uint32_t builtins = 5;
}
Type TypeStore::declareProduct(std::string name, bool copyRequested) {
  if (entries.size() >= std::numeric_limits<std::uint32_t>::max() - builtins)
    throw std::length_error("type identity limit exceeded");
  Type id(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({false, products.size()});
  products.push_back({std::move(name), {}, copyRequested});
  return id;
}
void TypeStore::defineProduct(Type type, std::vector<TypeField> fields) {
  products.at(entries.at(type.index() - builtins).index).fields =
      std::move(fields);
}
bool TypeStore::contains(Type type) const {
  return type != Type::Unknown && type.index() < builtins + entries.size();
}
bool TypeStore::isProduct(Type type) const {
  return type.index() >= builtins && contains(type) &&
         !entries[type.index() - builtins].view;
}
bool TypeStore::isView(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].view;
}
Type TypeStore::viewType(Type payload, ParameterMode mode) {
  for (std::size_t i = 0; i < entries.size(); ++i)
    if (entries[i].view && views[entries[i].index].payload == payload &&
        views[entries[i].index].mode == mode)
      return Type(builtins + static_cast<std::uint32_t>(i));
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({true, views.size()});
  views.push_back({payload, mode,
                   std::string(mode == ParameterMode::Read ? "read " : "mut ") +
                       std::string(name(payload))});
  return result;
}
const ViewType &TypeStore::view(Type type) const {
  return views.at(entries.at(type.index() - builtins).index);
}
void TypeStore::setDestructor(Type type, int function) {
  auto &record = products.at(entries.at(type.index() - builtins).index);
  record.hasDestructor = true;
  record.destructor = function;
}
bool TypeStore::needsDrop(Type type) const {
  if (!isProduct(type))
    return false;
  const auto &record = product(type);
  if (record.hasDestructor)
    return true;
  for (const auto &field : record.fields)
    if (needsDrop(field.type))
      return true;
  return false;
}
bool TypeStore::containsViews(Type type) const {
  if (isView(type))
    return true;
  if (isProduct(type))
    for (const auto &field : product(type).fields)
      if (containsViews(field.type))
        return true;
  return false;
}
const ProductType &TypeStore::product(Type type) const {
  return products.at(entries.at(type.index() - builtins).index);
}
std::string_view TypeStore::name(Type type) const {
  return isProduct(type) ? product(type).name
         : isView(type)  ? view(type).name
                         : typeName(type);
}
bool TypeStore::isCopy(Type type) const {
  return isView(type) ? view(type).mode == ParameterMode::Read
         : isProduct(type)
             ? product(type).copyRequested
             : type == Type::I32 || type == Type::Bool || type == Type::Unit;
}
} // namespace mettle
