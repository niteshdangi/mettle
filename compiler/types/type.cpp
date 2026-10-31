#include "types/type.h"
#include <algorithm>
#include <limits>
#include <stdexcept>
#include <utility>

namespace mettle {
std::optional<std::vector<std::pair<std::uint32_t, Type>>>
staticConstantFields(const TypeStore &types, const StaticConstant &constant) {
  if (!types.isProduct(constant.type))
    return std::nullopt;
  const auto &record = types.product(constant.type);
  std::vector<std::pair<std::uint32_t, Type>> result;
  if (record.layout.unionType) {
    if (constant.selection < 0 ||
        static_cast<std::size_t>(constant.selection) >= record.fields.size())
      return std::nullopt;
    result.emplace_back(constant.selection,
                        record.fields[constant.selection].type);
  } else if (types.isSum(constant.type)) {
    if (constant.selection < 0 ||
        static_cast<std::size_t>(constant.selection) >= record.variants.size())
      return std::nullopt;
    if (record.layout.kind != LayoutKind::Transparent)
      result.emplace_back(0, record.layout.tag);
    for (auto field : record.variants[constant.selection].fields)
      result.emplace_back(field, record.fields[field].type);
  } else if (types.compactArray(constant.type)) {
    if (constant.selection != -1 ||
        constant.kind == StaticConstant::Kind::Repeat)
      return std::nullopt;
    for (std::size_t i = 0; i < constant.fields.size(); ++i)
      result.emplace_back(i, record.components[0]);
  } else {
    if (constant.selection != -1)
      return std::nullopt;
    for (std::size_t i = 0; i < record.fields.size(); ++i)
      result.emplace_back(i, record.fields[i].type);
  }
  return result;
}

Type TypeStore::vectorType(std::string name, Type element, unsigned lanes,
                           unsigned alignment) {
  for (std::size_t i = 0; i < entries.size(); ++i)
    if (entries[i].kind == EntryKind::Product &&
        products[entries[i].index].kind == AggregateKind::NativeVector &&
        products[entries[i].index].name == name)
      return Type(builtinTypeCount + static_cast<std::uint32_t>(i));
  auto result = declareProduct(std::move(name), true);
  auto &record = products[entries[result.index() - builtinTypeCount].index];
  record.kind = AggregateKind::NativeVector;
  record.vector = ProductType::VectorShape{element, lanes, alignment};
  return result;
}
std::string_view typeName(Type type) {
  for (auto [candidate, name] : {std::pair{Type::I8, "i8"},
                                 {Type::I16, "i16"},
                                 {Type::I64, "i64"},
                                 {Type::I128, "i128"},
                                 {Type::Isize, "isize"},
                                 {Type::U16, "u16"},
                                 {Type::U32, "u32"},
                                 {Type::U64, "u64"},
                                 {Type::U128, "u128"},
                                 {Type::Usize, "usize"},
                                 {Type::F32, "f32"},
                                 {Type::F64, "f64"}})
    if (type == candidate)
      return name;
  if (type == Type::I32)
    return "i32";
  if (type == Type::Bool)
    return "bool";
  if (type == Type::Unit)
    return "Unit";
  if (type == Type::Never)
    return "Never";
  if (type == Type::Char)
    return "char";
  if (type == Type::U8)
    return "u8";
  if (type == Type::Unknown)
    return "<unresolved>";
  return "<invalid>";
}
namespace {
constexpr std::uint32_t builtins = builtinTypeCount;
}
Type TypeStore::declareProduct(std::string name, bool copyRequested) {
  if (entries.size() >= std::numeric_limits<std::uint32_t>::max() - builtins)
    throw std::length_error("type identity limit exceeded");
  Type id(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Product, products.size()});
  products.push_back({std::move(name), {}, copyRequested});
  return id;
}
void TypeStore::syncLookup() {
  for (; lookup.synced < entries.size(); ++lookup.synced) {
    auto i = static_cast<std::uint32_t>(lookup.synced);
    const auto &entry = entries[lookup.synced];
    switch (entry.kind) {
    case EntryKind::Product: {
      const auto &record = products[entry.index];
      if (record.genericOrigin != Type::Unknown)
        lookup.genericInstances[record.genericOrigin].push_back(i);
      if (record.regionOrigin != Type::Unknown)
        lookup.regionInstances[record.regionOrigin].push_back(i);
      lookup.aggregates[record.components].push_back(i);
      break;
    }
    case EntryKind::View: {
      const auto &record = views[entry.index];
      lookup.views.try_emplace(
          {record.payload, static_cast<int>(record.mode), record.region}, i);
      break;
    }
    case EntryKind::Pointer: {
      const auto &record = views[entry.index];
      lookup.pointers.try_emplace(
          {record.payload, static_cast<int>(record.mode)}, i);
      break;
    }
    case EntryKind::Slice:
      lookup.slices.try_emplace(slices[entry.index].element, i);
      break;
    case EntryKind::Erased:
      lookup.erased[erasedTypes[entry.index].declaration].push_back(i);
      break;
    case EntryKind::Parameter: {
      const auto &record = parameters[entry.index];
      if (record.kind == TypeParameterKind::Value)
        lookup.constants[{record.valueType, record.numeric.magnitude}]
            .push_back(i);
      else
        lookup.operands[record.operands].push_back(i);
      break;
    }
    case EntryKind::Callable:
      lookup.callables[callableKey(callables[entry.index])].push_back(i);
      break;
    default:
      break;
    }
  }
}
void TypeStore::defineProduct(Type type, std::vector<TypeField> fields) {
  products.at(entries.at(type.index() - builtins).index).fields =
      std::move(fields);
}
void TypeStore::setProductLayout(Type type, ProductLayout layout) {
  products.at(entries.at(type.index() - builtinTypeCount).index).layout =
      std::move(layout);
}
void TypeStore::defineEnumeration(Type type, std::vector<VariantType> variants,
                                  std::vector<TypeField> fields) {
  defineProduct(type, std::move(fields));
  auto &record = products.at(entries.at(type.index() - builtins).index);
  record.kind = AggregateKind::Enumeration;
  record.variants = std::move(variants);
}
bool TypeStore::isSum(Type type) const {
  return isProduct(type) && (product(type).kind == AggregateKind::Enumeration ||
                             product(type).kind == AggregateKind::Ordering ||
                             product(type).kind == AggregateKind::Optional ||
                             product(type).kind == AggregateKind::Outcome);
}
bool TypeStore::uninhabited(Type type) const {
  if (type == Type::Never)
    return true;
  if (!isProduct(type))
    return false;
  const auto &aggregate = product(type);
  if (isSum(type)) {
    for (const auto &variant : aggregate.variants) {
      bool impossible = false;
      for (auto field : variant.fields)
        impossible |= uninhabited(aggregate.fields[field].type);
      if (!impossible)
        return false;
    }
    return true;
  }
  for (const auto &field : aggregate.fields)
    if (uninhabited(field.type))
      return true;
  return false;
}
Type TypeStore::structural(AggregateKind kind, std::vector<Type> components,
                           std::uint32_t count) {
  if (kind == AggregateKind::Array && !components.empty() &&
      compactArrayShape(components[0], count))
    return arrayType(components[0], constant(Type::I32, count));
  syncLookup();
  if (auto existing =
          findIndexed(found(lookup.aggregates, components), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Product)
              return false;
            const auto &record = products[entries[i].index];
            return record.kind == kind && record.components == components &&
                   record.regionOrigin == Type::Unknown &&
                   (kind != AggregateKind::Array ||
                    (record.arrayCount == Type::Unknown &&
                     record.fields.size() == count));
          }))
    return *existing;
  std::vector<TypeField> fields;
  std::vector<VariantType> variants;
  std::string display;
  bool copy = true;
  for (auto component : components)
    copy &= isCopy(component);
  if (kind == AggregateKind::VarArgs) {
    display = "core::ffi::VarArgs";
    fields = {{"<cursor.0>", Type::U64},
              {"<cursor.1>", Type::U64},
              {"<cursor.2>", Type::U64}};
    copy = false;
  } else if (kind == AggregateKind::Ordering) {
    display = "core::sync::atomic::Ordering";
    fields = {{"<tag>", Type::I32}};
    variants = {{"Relaxed", {}},
                {"Release", {}},
                {"Acquire", {}},
                {"AcqRel", {}},
                {"SeqCst", {}}};
  } else if (kind == AggregateKind::PhantomPinned) {
    display = "core::marker::PhantomPinned";
  } else if (kind == AggregateKind::Coroutine) {
    display = "core::future::CoroutineState<" +
              std::string(name(components.at(0))) + ", " +
              std::string(name(components.at(1))) + ">";
    copy = false;
  } else if (kind == AggregateKind::BorrowError ||
             kind == AggregateKind::BorrowMutError) {
    display = kind == AggregateKind::BorrowError ? "core::cell::BorrowError"
                                                 : "core::cell::BorrowMutError";
  } else if (kind == AggregateKind::Ref || kind == AggregateKind::RefMut) {
    display = std::string(kind == AggregateKind::Ref ? "core::cell::Ref<"
                                                     : "core::cell::RefMut<") +
              std::string(
                  name(product(view(components.at(0)).payload).components[0])) +
              ">";
    fields = {{"<cell>", components[0]}};
    copy = false;
  } else if (kind == AggregateKind::Uninit ||
             kind == AggregateKind::ManualDrop ||
             kind == AggregateKind::UnsafeCell || kind == AggregateKind::Cell ||
             kind == AggregateKind::RefCell || kind == AggregateKind::Pin ||
             kind == AggregateKind::Atomic) {
    auto label = kind == AggregateKind::Uninit       ? "core::mem::MaybeUninit"
                 : kind == AggregateKind::ManualDrop ? "core::mem::ManuallyDrop"
                 : kind == AggregateKind::UnsafeCell ? "core::cell::UnsafeCell"
                 : kind == AggregateKind::Cell       ? "core::cell::Cell"
                 : kind == AggregateKind::RefCell    ? "core::cell::RefCell"
                 : kind == AggregateKind::Pin ? "pinned"
                                              : "core::sync::atomic::Atomic";
    display =
        std::string(label) + "<" + std::string(name(components.at(0))) + ">";
    fields = {{"<storage>", components[0]}};
    if (kind == AggregateKind::RefCell)
      fields.insert(fields.begin(), {"<borrows>", Type::Isize});
    if (kind == AggregateKind::UnsafeCell || kind == AggregateKind::Atomic ||
        kind == AggregateKind::Cell || kind == AggregateKind::RefCell)
      copy = false;
  } else if (kind == AggregateKind::Optional) {
    display = "(" + std::string(name(components.at(0))) + ")?";
    fields = {{"<tag>", Type::I32}, {"value", components[0]}};
    variants = {{"none", {}}, {"present", {1}}};
  } else if (kind == AggregateKind::Outcome) {
    display = "(" + std::string(name(components.at(0))) + " throws " +
              std::string(name(components.at(1))) + ")";
    fields = {{"<tag>", Type::I32},
              {"value", components[0]},
              {"error", components[1]}};
    variants = {{"success", {1}}, {"failure", {2}}};
  } else {
    display = kind == AggregateKind::Tuple ? "(" : "[";
    auto size = kind == AggregateKind::Array ? count : components.size();
    for (std::size_t i = 0; i < size; ++i) {
      auto component = components[kind == AggregateKind::Array ? 0 : i];
      fields.push_back({std::to_string(i), component});
      if (kind != AggregateKind::Array) {
        if (i)
          display += ", ";
        display += name(component);
      }
    }
    if (kind == AggregateKind::Array)
      display +=
          std::string(name(components[0])) + "; " + std::to_string(count);
    display += kind == AggregateKind::Tuple ? ")" : "]";
  }
  auto result = declareProduct(std::move(display), copy);
  defineProduct(result, std::move(fields));
  auto &record = products.at(entries.at(result.index() - builtins).index);
  record.kind = kind;
  record.variants = std::move(variants);
  record.components = std::move(components);
  if (kind == AggregateKind::Ref || kind == AggregateKind::RefMut)
    record.nativeCleanup = kind == AggregateKind::Ref
                               ? NativeCleanup::RefRelease
                               : NativeCleanup::RefMutRelease;
  return result;
}
bool TypeStore::contains(Type type) const {
  return type != Type::Unknown && type.index() < builtins + entries.size();
}
bool TypeStore::isProduct(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Product;
}
bool TypeStore::isView(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::View;
}
bool TypeStore::isPointer(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Pointer;
}
Type TypeStore::pointerType(Type payload, ParameterMode mode) {
  syncLookup();
  if (auto existing = lookup.pointers.find({payload, static_cast<int>(mode)});
      existing != lookup.pointers.end())
    return Type(builtins + existing->second);
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Pointer, views.size()});
  views.push_back(
      {payload, mode,
       "ptr<" + std::string(mode == ParameterMode::Read ? "read " : "mut ") +
           std::string(name(payload)) + ">"});
  return result;
}
const ViewType &TypeStore::pointer(Type type) const { return view(type); }
Type TypeStore::viewType(Type payload, ParameterMode mode, RegionId region) {
  syncLookup();
  if (auto existing =
          lookup.views.find({payload, static_cast<int>(mode), region});
      existing != lookup.views.end())
    return Type(builtins + existing->second);
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::View, views.size()});
  views.push_back({payload, mode,
                   std::string(mode == ParameterMode::Read ? "read " : "mut ") +
                       std::string(name(payload)),
                   region});
  return result;
}
const ViewType &TypeStore::view(Type type) const {
  return views.at(entries.at(type.index() - builtins).index);
}
bool TypeStore::isSlice(Type type) const {
  return type.index() >= builtins && contains(type) &&
         entries[type.index() - builtins].kind == EntryKind::Slice;
}
Type TypeStore::sliceType(Type element) {
  syncLookup();
  if (auto existing = lookup.slices.find(element);
      existing != lookup.slices.end())
    return Type(builtins + existing->second);
  Type result(builtins + static_cast<std::uint32_t>(entries.size()));
  entries.push_back({EntryKind::Slice, slices.size()});
  slices.push_back({element, "[" + std::string(name(element)) + "]"});
  return result;
}
const SliceType &TypeStore::slice(Type type) const {
  return slices.at(entries.at(type.index() - builtins).index);
}
Type TypeStore::regionalProduct(Type origin, std::vector<TypeField> fields,
                                std::vector<RegionId> arguments,
                                bool normalizedFields) {
  auto record = product(origin);
  normalizedFields |= record.normalizedFields;
  if (record.kind == AggregateKind::Cell ||
      record.kind == AggregateKind::RefCell ||
      record.kind == AggregateKind::Ref || record.kind == AggregateKind::RefMut)
    return structural(record.kind,
                      {fields.at(cellPayloadField(record.kind)).type});
  while (product(origin).regionOrigin != Type::Unknown)
    origin = product(origin).regionOrigin;
  syncLookup();
  if (auto existing = findIndexed(
          found(lookup.regionInstances, origin), [&](std::size_t i) {
            if (entries[i].kind != EntryKind::Product)
              return false;
            const auto &record = products[entries[i].index];
            return record.regionOrigin == origin &&
                   record.normalizedFields == normalizedFields &&
                   record.regionArguments == arguments &&
                   record.fields.size() == fields.size() &&
                   std::equal(record.fields.begin(), record.fields.end(),
                              fields.begin(),
                              [](const auto &left, const auto &right) {
                                return left.name == right.name &&
                                       left.type == right.type;
                              });
          }))
    return *existing;
  record.fields = std::move(fields);
  record.regionOrigin = origin;
  record.regionArguments = std::move(arguments);
  record.normalizedFields = normalizedFields;
  auto result = declareProduct(record.name, record.copyRequested);
  products.at(entries.at(result.index() - builtins).index) = std::move(record);
  return result;
}
Type TypeStore::regionalShell(Type origin, std::vector<RegionId> regions,
                              std::vector<Type> arguments, Type pattern) {
  auto record = product(origin);
  while (product(origin).regionOrigin != Type::Unknown)
    origin = product(origin).regionOrigin;
  record.fields.clear();
  record.regionOrigin = origin;
  record.regionArguments = std::move(regions);
  record.genericArguments = std::move(arguments);
  if (pattern != Type::Unknown)
    record.regionPattern = pattern;
  auto result = declareProduct(record.name, record.copyRequested);
  products.at(entries.at(result.index() - builtins).index) = std::move(record);
  return result;
}
void TypeStore::setRegionPattern(Type type, Type pattern) {
  products.at(entries.at(type.index() - builtins).index).regionPattern =
      pattern;
}
void TypeStore::setDestructor(Type type, int function) {
  auto &record = products.at(entries.at(type.index() - builtins).index);
  record.hasDestructor = true;
  record.destructor = function;
}
void TypeStore::setNativeCleanup(Type type, NativeCleanup action) {
  products.at(entries.at(type.index() - builtins).index).nativeCleanup = action;
}
bool TypeStore::needsDrop(Type type) const {
  if (isErased(type))
    return true;
  if (isSlice(type))
    return needsDrop(slice(type).element);
  if (isParameter(type))
    return !parameter(type).copyRequested;
  if (!isProduct(type))
    return false;
  if (product(type).kind == AggregateKind::Uninit ||
      product(type).kind == AggregateKind::ManualDrop ||
      product(type).kind == AggregateKind::Atomic)
    return false;
  const auto &record = product(type);
  if (record.kind == AggregateKind::VarArgs ||
      record.kind == AggregateKind::Coroutine)
    return true;
  if (record.kind == AggregateKind::Array &&
      record.arrayCount != Type::Unknown && !record.components.empty() &&
      needsDrop(record.components[0]))
    return true;
  if (record.hasDestructor || record.nativeCleanup != NativeCleanup::None)
    return true;
  for (const auto &field : record.fields)
    if (needsDrop(field.type))
      return true;
  return false;
}
bool TypeStore::containsViews(Type type) const {
  if (isView(type))
    return true;
  if (isSlice(type))
    return containsViews(slice(type).element);
  if (isProduct(type)) {
    const auto &record = product(type);
    if (record.kind == AggregateKind::Array &&
        record.arrayCount != Type::Unknown && !record.components.empty() &&
        containsViews(record.components[0]))
      return true;
    if (record.kind == AggregateKind::Coroutine)
      return containsViews(record.components[1]);
    for (const auto &field : product(type).fields)
      if (containsViews(field.type))
        return true;
  }
  return false;
}
const ProductType &TypeStore::product(Type type) const {
  return products.at(entries.at(type.index() - builtins).index);
}
std::string_view TypeStore::name(Type type) const {
  return isErased(type)                          ? erased(type).name
         : isProduct(type)                       ? product(type).name
         : isView(type) || isPointer(type)       ? view(type).name
         : isSlice(type)                         ? slice(type).name
         : isFunctionPointer(type)               ? callable(type).name
         : isParameter(type) || isConstant(type) ? parameter(type).name
                                                 : typeName(type);
}
bool TypeStore::isCopy(Type type) const {
  return isFunctionPointer(type) || isPointer(type) ? true
         : isParameter(type) ? parameter(type).copyRequested
         : isView(type)      ? view(type).mode == ParameterMode::Read
         : isProduct(type)   ? product(type).copyRequested
                             : isNumeric(type) || type == Type::Bool ||
                                   type == Type::Unit || type == Type::Never ||
                                   type == Type::Char || type == Type::U8;
}
bool TypeStore::isUnpin(Type type) const {
  if (isParameter(type))
    return parameter(type).unpin;
  if (isOpaque(type))
    return product(type).layout.unpin == 1;
  if (!isProduct(type))
    return contains(type);
  const auto &record = product(type);
  auto origin = type;
  while (product(origin).regionOrigin != Type::Unknown)
    origin = product(origin).regionOrigin;
  if (product(origin).genericOrigin != Type::Unknown)
    origin = product(origin).genericOrigin;
  const auto &property = product(origin).layout;
  if (property.unpin >= 0) {
    if (!property.unpin || property.conditionalUnpin)
      return false;
    const auto &arguments = record.genericArguments.empty()
                                ? record.genericParameters
                                : record.genericArguments;
    for (auto [index, requirements] : property.unpinConditions)
      if (index >= arguments.size() ||
          ((requirements & 1) && !isCopy(arguments[index])) ||
          ((requirements & 2) && !isSized(arguments[index])) ||
          ((requirements & 4) && !isUnpin(arguments[index])))
        return false;
    return true;
  }
  if (record.kind == AggregateKind::PhantomPinned ||
      record.kind == AggregateKind::Coroutine)
    return false;
  for (const auto &field : record.fields)
    if (!isUnpin(field.type))
      return false;
  return true;
}
void TypeStore::constrainUnpin(Type type) {
  parameters.at(entries.at(type.index() - builtins).index).unpin = true;
}
} // namespace mettle
