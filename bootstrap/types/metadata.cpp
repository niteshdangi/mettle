#include "types/type.h"
#include <functional>
#include <set>

namespace mettle {
PointerMetadata TypeStore::pointerMetadata(Type type) const {
  std::set<Type> visited;
  while (visited.insert(type).second) {
    if (isErased(type))
      return PointerMetadata::Witness;
    if (isSlice(type))
      return PointerMetadata::ElementCount;
    if (isParameter(type) && !isSized(type))
      return PointerMetadata::Dependent;
    if (!isProduct(type) || product(type).fields.empty())
      return PointerMetadata::None;
    type = product(type).fields.back().type;
  }
  return PointerMetadata::Dependent;
}

namespace {
std::optional<std::pair<Type, Type>>
tailConversion(const TypeStore &types, Type source, Type target, bool erased) {
  std::set<std::pair<Type, Type>> active;
  std::function<std::optional<std::pair<Type, Type>>(Type, Type)> eligible =
      [&](Type from, Type to) -> std::optional<std::pair<Type, Type>> {
    if (!active.emplace(from, to).second)
      return std::nullopt;
    std::optional<std::pair<Type, Type>> result;
    if (erased && types.isErased(to))
      result = std::pair(from, to);
    else if (!erased && types.isProduct(from) &&
             types.product(from).kind == AggregateKind::Array &&
             types.isSlice(to) &&
             types.product(from).components[0] == types.slice(to).element)
      result = std::pair(from, to);
    else if (types.isProduct(from) && types.isProduct(to)) {
      const auto &a = types.product(from), &b = types.product(to);
      auto originA = a.genericOrigin == Type::Unknown ? from : a.genericOrigin;
      auto originB = b.genericOrigin == Type::Unknown ? to : b.genericOrigin;
      bool cell =
          (a.kind == AggregateKind::Cell || a.kind == AggregateKind::RefCell ||
           a.kind == AggregateKind::ManualDrop ||
           a.kind == AggregateKind::UnsafeCell) &&
          a.kind == b.kind;
      bool valid = (originA == originB || cell) && !a.fields.empty() &&
                   a.fields.size() == b.fields.size() &&
                   a.genericArguments.size() == b.genericArguments.size();
      std::size_t changed = 0;
      for (std::size_t p = 0; valid && p < a.genericArguments.size(); ++p)
        if (a.genericArguments[p] != b.genericArguments[p])
          valid = ++changed == 1 &&
                  eligible(a.genericArguments[p], b.genericArguments[p])
                      .has_value();
      for (std::size_t p = 0; valid && p + 1 < a.fields.size(); ++p)
        valid = a.fields[p].type == b.fields[p].type;
      if (valid)
        result = eligible(a.fields.back().type, b.fields.back().type);
    }
    active.erase({from, to});
    return result;
  };
  return eligible(source, target);
}
} // namespace
std::optional<Type> TypeStore::unsizedArray(Type source, Type target) const {
  auto conversion = tailConversion(*this, source, target, false);
  return conversion ? std::optional<Type>(conversion->first) : std::nullopt;
}
std::optional<std::pair<Type, Type>> TypeStore::erasedTail(Type source,
                                                           Type target) const {
  return tailConversion(*this, source, target, true);
}
} // namespace mettle
