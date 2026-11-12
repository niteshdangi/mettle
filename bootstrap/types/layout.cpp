#include "types/layout.h"
#include <algorithm>
#include <functional>
#include <limits>
#include <map>
#include <set>

namespace mettle {
std::optional<std::uint64_t> textConstantCount(const TypeStore &types,
                                               const StaticConstant &value) {
  if (value.kind != StaticConstant::Kind::Text || !types.contains(value.type) ||
      (!types.isView(value.type) && !types.isPointer(value.type)) ||
      value.symbol != -1 || !value.projections.empty() ||
      value.selection != -1 || value.scalar != NumericLiteral{} ||
      value.text.size() >
          integerMaximum(Type::Isize, types.targetPointerBits()).magnitude[0] ||
      value.byteOffset > value.text.size() || value.fields.size() > 1)
    return std::nullopt;
  const auto &view = types.view(value.type);
  if (types.isView(value.type) && view.mode != ParameterMode::Read)
    return std::nullopt;
  auto count = static_cast<std::uint64_t>(value.text.size());
  if (!value.fields.empty()) {
    const auto &extent = value.fields.front();
    if (extent.kind != StaticConstant::Kind::Scalar ||
        extent.type != Type::Usize || !extent.fields.empty() ||
        extent.scalar.floatingBits || !extent.scalar.floating.empty() ||
        extent.scalar.negative || extent.scalar.magnitude[1] ||
        !integerLiteralFits(extent.scalar, Type::Usize,
                            types.targetPointerBits()))
      return std::nullopt;
    count = extent.scalar.magnitude[0];
  }
  auto target = view.payload;
  auto metadata = types.pointerMetadata(target);
  if (metadata == PointerMetadata::None && types.isPointer(value.type))
    return value.fields.empty() ? std::optional(count) : std::nullopt;
  if (metadata == PointerMetadata::ElementCount) {
    while (types.isProduct(target) &&
           types.product(target).kind == AggregateKind::Product &&
           types.product(target).fields.size() == 1) {
      auto layout = objectLayout(types, target);
      if (!layout || layout->alignment != 1 || layout->fields.size() != 1 ||
          layout->fields.front() != 0)
        return std::nullopt;
      target = types.product(target).fields.front().type;
    }
    if (!types.isSlice(target))
      return std::nullopt;
    target = types.slice(target).element;
  } else if (metadata != PointerMetadata::None || !value.fields.empty())
    return std::nullopt;
  auto leaf = target;
  while (types.isProduct(leaf) &&
         types.product(leaf).kind == AggregateKind::Array) {
    if (types.product(leaf).components.empty())
      return std::nullopt;
    leaf = types.product(leaf).components.front();
  }
  auto layout = objectLayout(types, target);
  if (leaf != Type::U8 || !layout || layout->alignment != 1)
    return std::nullopt;
  auto remaining = value.text.size() - value.byteOffset;
  if (metadata == PointerMetadata::ElementCount) {
    if (layout->size && count > remaining / layout->size)
      return std::nullopt;
  } else if (layout->size > remaining)
    return std::nullopt;
  return count;
}

std::optional<ObjectLayout> objectLayout(const TypeStore &types, Type type) {
  std::set<Type> active;
  std::map<Type, ObjectLayout> summaries;
  auto align = [](std::uint64_t value, std::uint64_t alignment) {
    return (value + alignment - 1) & ~(alignment - 1);
  };
  std::function<std::optional<ObjectLayout>(Type)> visit =
      [&](Type current) -> std::optional<ObjectLayout> {
    if (auto found = summaries.find(current); found != summaries.end())
      return found->second;
    ObjectLayout result;
    auto complete = [&]() {
      auto summary = result;
      summary.fields.clear();
      summaries[current] = std::move(summary);
      active.erase(current);
      return result;
    };
    if (isInteger(current) || current == Type::Char || current == Type::Bool) {
      result.size = std::max(1u, integerWidth(current) / 8);
      result.alignment = result.size;
      return result;
    }
    if (isFloating(current)) {
      result.size = result.alignment = current == Type::F32 ? 4 : 8;
      return result;
    }
    if (current == Type::Unit || current == Type::Never)
      return result;
    if (types.isFunctionPointer(current)) {
      result.size = result.alignment = 8;
      return result;
    }
    if (types.isSlice(current)) {
      auto element = visit(types.slice(current).element);
      if (!element)
        return std::nullopt;
      result.alignment = element->alignment;
      return result;
    }
    if (types.isErased(current))
      return result;
    if (types.isView(current) || types.isPointer(current)) {
      auto metadata = types.pointerMetadata(types.view(current).payload);
      if (metadata == PointerMetadata::Dependent)
        return std::nullopt;
      result.size = metadata == PointerMetadata::ElementCount ? 16
                    : metadata == PointerMetadata::Witness    ? 24
                                                              : 8;
      result.alignment = 8;
      if (metadata == PointerMetadata::ElementCount)
        result.fields = {0, 8};
      else if (metadata == PointerMetadata::Witness)
        result.fields = {0, 8, 16};
      return result;
    }
    if (!types.isProduct(current) || !active.insert(current).second)
      return std::nullopt;
    const auto &record = types.product(current);
    if (record.vector) {
      auto element = visit(record.vector->element);
      if (!element)
        return std::nullopt;
      result.size = element->size * record.vector->lanes;
      result.alignment = record.vector->alignment;
      return complete();
    }
    if (record.kind == AggregateKind::Enumeration && record.variants.empty()) {
      active.erase(current);
      result.alignment = std::max<std::uint64_t>(1, record.layout.alignment);
      return result;
    }
    if (record.kind == AggregateKind::Coroutine) {
      active.erase(current);
      auto physical = types.coroutineLayout(current);
      if (!physical)
        return std::nullopt;
      result.size = physical->first;
      result.alignment = physical->second;
      return result;
    }
    if (record.kind == AggregateKind::Opaque) {
      auto hidden = visit(record.fields[0].type);
      active.erase(current);
      if (hidden)
        hidden->fields = {0};
      return hidden;
    }
    if (record.kind == AggregateKind::Array) {
      if (record.components.empty())
        return std::nullopt;
      auto length = types.arrayLength(current);
      if (!length)
        return std::nullopt;
      auto element = visit(record.components[0]);
      if (!element)
        return std::nullopt;
      auto count = *length;
      auto stride = align(element->size, element->alignment);
      if (count && stride > std::numeric_limits<std::uint64_t>::max() / count)
        return std::nullopt;
      result.size = stride * count;
      result.alignment = element->alignment;
      result.unaligned = count && element->unaligned;
      // Compact arrays have no per-element field offsets.
      if (!types.compactArray(current)) {
        result.fields.resize(count);
        for (std::size_t i = 0; i < count; ++i)
          result.fields[i] = stride * i;
      }
      return complete();
    }
    std::vector<ObjectLayout> members;
    for (const auto &field : record.fields) {
      auto layout = visit(field.type);
      if (!layout) {
        active.erase(current);
        return std::nullopt;
      }
      members.push_back(std::move(*layout));
    }
    if (record.kind == AggregateKind::Array && members.empty()) {
      auto element = visit(record.components[0]);
      active.erase(current);
      if (!element)
        return std::nullopt;
      result.alignment = element->alignment;
      return result;
    }
    if (record.kind == AggregateKind::Enumeration &&
        !record.layout.discriminants.empty() &&
        record.layout.kind != LayoutKind::Transparent) {
      auto tag = visit(record.layout.tag);
      if (!tag) {
        active.erase(current);
        return std::nullopt;
      }
      result.fields.resize(members.size());
      result.alignment = tag->alignment;
      std::uint64_t payloadAlignment = 1;
      for (std::size_t i = 1; i < members.size(); ++i)
        payloadAlignment = std::max(payloadAlignment, members[i].alignment);
      result.alignment = std::max(result.alignment, payloadAlignment);
      auto payload = record.layout.kind == LayoutKind::C
                         ? align(tag->size, payloadAlignment)
                         : tag->size;
      result.size = tag->size;
      for (const auto &variant : record.variants) {
        auto size = payload;
        for (auto field : variant.fields) {
          size = align(size, members[field].alignment);
          result.fields[field] = size;
          result.unaligned |= members[field].unaligned;
          if (size > std::numeric_limits<std::uint64_t>::max() -
                         members[field].size - ((std::uint64_t{1} << 29) - 1)) {
            active.erase(current);
            return std::nullopt;
          }
          size += members[field].size;
        }
        result.size = std::max(result.size, size);
      }
      result.alignment = std::max(result.alignment, record.layout.alignment);
      result.size = align(result.size, result.alignment);
      return complete();
    }
    if (record.layout.kind == LayoutKind::Transparent) {
      std::size_t relevant = 0;
      auto first = record.kind == AggregateKind::Enumeration ? 1u : 0u;
      for (std::size_t i = first; i < members.size(); ++i) {
        const auto &member = members[i];
        if (member.size || member.alignment != 1) {
          result = member;
          ++relevant;
        }
      }
      if (relevant > 1) {
        active.erase(current);
        return std::nullopt;
      }
      result.fields.assign(members.size(), 0);
    } else {
      result.fields.resize(members.size());
      for (std::size_t i = 0; i < members.size(); ++i) {
        auto alignment = record.layout.packing ? std::min(record.layout.packing,
                                                          members[i].alignment)
                                               : members[i].alignment;
        result.alignment = std::max(result.alignment, alignment);
        auto offset =
            record.layout.unionType ? 0 : align(result.size, alignment);
        result.fields[i] = offset;
        result.unaligned |=
            members[i].unaligned || offset % members[i].alignment != 0;
        if (offset > std::numeric_limits<std::uint64_t>::max() -
                         members[i].size - ((std::uint64_t{1} << 29) - 1)) {
          active.erase(current);
          return std::nullopt;
        }
        result.size = std::max(result.size, offset + members[i].size);
      }
      if (record.layout.alignment)
        result.alignment = std::max(result.alignment, record.layout.alignment);
      result.size = align(result.size, result.alignment);
    }
    return complete();
  };
  return visit(type);
}
bool coroutineDependent(const TypeStore &types, Type type) {
  std::set<Type> visited;
  std::function<bool(Type)> visit = [&](Type current) {
    if (!types.isProduct(current) || !visited.insert(current).second)
      return false;
    const auto &record = types.product(current);
    if (record.kind == AggregateKind::Coroutine)
      return true;
    if (record.kind == AggregateKind::Array && !record.components.empty())
      return visit(record.components[0]);
    return std::any_of(record.fields.begin(), record.fields.end(),
                       [&](const auto &field) { return visit(field.type); });
  };
  return visit(type);
}
bool customRepresentation(const TypeStore &types, Type type) {
  std::set<Type> visited;
  std::function<bool(Type)> visit = [&](Type current) {
    if (!types.isProduct(current) || !visited.insert(current).second)
      return false;
    const auto &record = types.product(current);
    const auto &layout = record.layout;
    if (record.kind == AggregateKind::Array && record.fields.empty())
      return true;
    if (layout.kind != LayoutKind::Native || layout.alignment ||
        layout.packing || layout.unionType || !layout.discriminants.empty())
      return true;
    for (const auto &field : record.fields)
      if (visit(field.type))
        return true;
    return false;
  };
  return visit(type);
}
bool cCompatible(const TypeStore &types, Type type) {
  std::set<Type> active;
  std::function<bool(Type)> visit = [&](Type current) {
    if (isNumeric(current) || current == Type::Bool || current == Type::Char ||
        current == Type::Unit || current == Type::Never)
      return true;
    if (types.isProduct(current) && types.product(current).vector)
      return true;
    if (types.isPointer(current) || types.isView(current))
      return types.pointerMetadata(types.view(current).payload) ==
             PointerMetadata::None;
    if (!active.insert(current).second)
      return true;
    bool result = false;
    if (types.isFunctionPointer(current)) {
      const auto &signature = types.callable(current);
      result = signature.abi == "C" || signature.abi == "C-unwind" ||
               signature.abi == "system";
      result &= visit(signature.result);
      for (const auto &parameter : signature.parameters)
        result &= parameter.mode == ParameterMode::Read ||
                          parameter.mode == ParameterMode::Mut
                      ? types.isSized(parameter.type)
                      : visit(parameter.type);
    } else if (types.isProduct(current)) {
      const auto &record = types.product(current);
      result = record.layout.kind != LayoutKind::Native ||
               record.kind == AggregateKind::Array;
      if (record.kind == AggregateKind::Array && !record.components.empty())
        result &= visit(record.components[0]);
      else
        for (const auto &field : record.fields)
          result &= visit(field.type);
    }
    active.erase(current);
    return result;
  };
  return visit(type);
}
bool fieldlessEnumeration(const TypeStore &types, Type type) {
  return types.isProduct(type) &&
         types.product(type).kind == AggregateKind::Enumeration &&
         std::all_of(
             types.product(type).variants.begin(),
             types.product(type).variants.end(),
             [](const auto &variant) { return variant.fields.empty(); });
}
} // namespace mettle
