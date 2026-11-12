#include "types/machine.h"
#include "types/layout.h"
#include "types/target.h"
#include <algorithm>
#include <functional>
#include <set>

namespace mettle {
bool constantFloatMethod(std::string_view name) {
  constexpr std::string_view names[]{"abs",
                                     "ceil",
                                     "clamp",
                                     "copysign",
                                     "floor",
                                     "fract",
                                     "from_be_bytes",
                                     "from_bits",
                                     "from_le_bytes",
                                     "from_ne_bytes",
                                     "is_finite",
                                     "is_infinite",
                                     "is_nan",
                                     "is_normal",
                                     "is_sign_negative",
                                     "is_sign_positive",
                                     "is_subnormal",
                                     "max",
                                     "midpoint",
                                     "min",
                                     "mul_add",
                                     "next_down",
                                     "next_up",
                                     "recip",
                                     "round",
                                     "round_ties_even",
                                     "signum",
                                     "to_be_bytes",
                                     "to_bits",
                                     "to_degrees",
                                     "to_le_bytes",
                                     "to_ne_bytes",
                                     "to_radians",
                                     "trunc"};
  return std::find(std::begin(names), std::end(names), name) != std::end(names);
}
bool containsVarArgs(const TypeStore &types, Type type) {
  std::set<Type> visited;
  std::function<bool(Type)> visit = [&](Type current) {
    if (!visited.insert(current).second)
      return false;
    if (types.isView(current) || types.isPointer(current))
      return visit(types.view(current).payload);
    if (!types.isProduct(current))
      return false;
    if (types.product(current).kind == AggregateKind::VarArgs)
      return true;
    // Array elements share one type.
    if (types.product(current).kind == AggregateKind::Array &&
        !types.product(current).components.empty())
      return visit(types.product(current).components[0]);
    for (const auto &field : types.product(current).fields)
      if (visit(field.type))
        return true;
    return false;
  };
  return visit(type);
}
bool machineCastAllowed(const TypeStore &types, Type source, Type target) {
  if (scalarCastAllowed(source, target))
    return true;
  if (fieldlessEnumeration(types, source) && isInteger(target))
    return true;
  return types.isPointer(target) &&
         ((types.isView(source) &&
           types.view(source).payload == types.pointer(target).payload &&
           (types.pointer(target).mode == ParameterMode::Read ||
            types.view(source).mode == ParameterMode::Mut)) ||
          (types.isPointer(source) &&
           (types.pointerMetadata(types.pointer(target).payload) ==
                PointerMetadata::None ||
            types.pointerMetadata(types.pointer(source).payload) ==
                types.pointerMetadata(types.pointer(target).payload))));
}
std::optional<MachineSignature>
machineSignature(const TypeStore &types, std::string_view operation,
                 std::span<const Type> operands, Type argument,
                 std::span<const Type> unpinProofs) {
  using Shape = MachineSignature::Shape;
  auto signature = [](Type value, Shape shape = Shape::Value,
                      bool unsafeCall = false) {
    return std::optional<MachineSignature>{{value, shape, unsafeCall}};
  };
  if (operation.starts_with("va.")) {
    auto cursor = [&](Type type) {
      return types.isProduct(type) &&
             types.product(type).kind == AggregateKind::VarArgs;
    };
    if (operation == "va.start")
      return operands.empty() && cursor(argument) ? signature(argument)
                                                  : std::nullopt;
    if (operands.size() != 1)
      return std::nullopt;
    if (operation == "va.end")
      return cursor(operands[0]) ? signature(Type::Unit) : std::nullopt;
    if (!types.isView(operands[0]) || !cursor(types.view(operands[0]).payload))
      return std::nullopt;
    if (operation == "va.copy")
      return signature(types.view(operands[0]).payload);
    if (operation != "va.arg" ||
        types.view(operands[0]).mode != ParameterMode::Mut)
      return std::nullopt;
    std::set<Type> active;
    std::function<bool(Type)> compatible = [&](Type type) {
      if (!types.isCopy(type))
        return false;
      if (isNumeric(type) || type == Type::Char)
        return true;
      if (nativeVector(types, type))
        return true;
      if (types.isPointer(type))
        return types.pointerMetadata(types.pointer(type).payload) ==
               PointerMetadata::None;
      if (types.isFunctionPointer(type))
        return types.callable(type).abi == "C" ||
               types.callable(type).abi == "C-unwind" ||
               types.callable(type).abi == "system";
      if (!types.isProduct(type) || !active.insert(type).second)
        return false;
      const auto &record = types.product(type);
      bool valid = record.layout.kind != LayoutKind::Native ||
                   record.kind == AggregateKind::Array;
      if (record.kind == AggregateKind::Array && !record.components.empty()) {
        auto element = record.components[0];
        valid &= compatible(element) || element == Type::Unit ||
                 element == Type::Bool || element == Type::Char;
      } else
        for (const auto &field : record.fields)
          valid &= compatible(field.type) || field.type == Type::Unit ||
                   field.type == Type::Bool || field.type == Type::Char;
      active.erase(type);
      return valid;
    };
    Type promoted = argument;
    while (types.isProduct(promoted) &&
           types.product(promoted).layout.kind == LayoutKind::Transparent) {
      auto next = Type::Unit;
      const auto &record = types.product(promoted);
      for (std::size_t i = record.kind == AggregateKind::Enumeration ? 1 : 0;
           i < record.fields.size(); ++i)
        if (auto layout = objectLayout(types, record.fields[i].type);
            layout && layout->size)
          next = record.fields[i].type;
      promoted = next;
    }
    if (fieldlessEnumeration(types, promoted))
      promoted = types.product(promoted).layout.tag;
    bool promotion = promoted == Type::Bool || promoted == Type::F32 ||
                     (isInteger(promoted) && integerWidth(promoted) < 32);
    return !promotion && compatible(argument)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  }
  auto unpin = [&](Type type) {
    return types.isUnpin(type) ||
           std::find(unpinProofs.begin(), unpinProofs.end(), type) !=
               unpinProofs.end();
  };
  if (operation.starts_with("cell.")) {
    if (!types.isProduct(argument))
      return std::nullopt;
    const auto &cell = types.product(argument);
    auto method = operation.substr(5);
    bool guarded =
        cell.kind == AggregateKind::Ref || cell.kind == AggregateKind::RefMut;
    if (guarded) {
      if (operands.size() != 1 || !types.isView(operands[0]) ||
          types.view(operands[0]).payload != argument)
        return std::nullopt;
      auto owner = types.view(cell.components[0]).payload;
      auto payload = types.product(owner).components[0];
      if (method == "get_ref")
        return signature(payload, Shape::ViewRead);
      if (method == "get_mut" && cell.kind == AggregateKind::RefMut &&
          types.view(operands[0]).mode == ParameterMode::Mut)
        return signature(payload, Shape::ViewMut);
      if (method == "clone" && cell.kind == AggregateKind::Ref)
        return signature(owner, Shape::Ref);
      return std::nullopt;
    }
    if (cell.kind != AggregateKind::Cell && cell.kind != AggregateKind::RefCell)
      return std::nullopt;
    auto payload = cell.components[0];
    if (method == "new")
      return operands.size() == 1 && operands[0] == payload &&
                     types.isSized(payload)
                 ? signature(argument)
                 : std::nullopt;
    if (method == "into_inner")
      return operands.size() == 1 && operands[0] == argument &&
                     types.isSized(payload)
                 ? signature(payload)
                 : std::nullopt;
    if (operands.empty() || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    if (method == "get_mut")
      return operands.size() == 1 &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (method == "as_ptr")
      return operands.size() == 1 ? signature(payload, Shape::PointerMut)
                                  : std::nullopt;
    if (method == "get")
      return cell.kind == AggregateKind::Cell && operands.size() == 1 &&
                     types.isCopy(payload)
                 ? signature(payload)
                 : std::nullopt;
    if (method == "replace" || method == "set")
      return operands.size() == 2 && operands[1] == payload &&
                     types.isSized(payload) &&
                     (method != "set" || cell.kind == AggregateKind::Cell)
                 ? signature(method == "set" ? Type::Unit : payload)
                 : std::nullopt;
    if (method == "swap")
      return operands.size() == 2 && types.isSized(payload) &&
                     types.isView(operands[1]) &&
                     types.view(operands[1]).payload == argument
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (cell.kind == AggregateKind::RefCell && operands.size() == 1) {
      if (method == "borrow")
        return signature(argument, Shape::Ref);
      if (method == "borrow_mut")
        return signature(argument, Shape::RefMut);
      if (method == "try_borrow")
        return signature(argument, Shape::TryRef);
      if (method == "try_borrow_mut")
        return signature(argument, Shape::TryRefMut);
    }
    return std::nullopt;
  }
  if (auto target = targetOperation(operation)) {
    if (!nativeVector(types, argument) ||
        types.name(argument) != target->vector ||
        operands.size() != target->arguments)
      return std::nullopt;
    using K = TargetOperation::Kind;
    for (std::size_t i = 0; i < operands.size(); ++i) {
      auto actual = operands[i];
      auto expected = argument;
      if (target->kind == K::Splat || target->kind == K::Set ||
          (target->kind == K::Insert && i == 0))
        expected = target->element;
      else if (target->kind == K::Load ||
               (target->kind == K::Store && i == 0)) {
        auto descriptor = *targetVector(target->vector);
        auto pointee =
            descriptor.arch == TargetArch::X86_64 ? argument : target->element;
        if (!types.isPointer(actual) ||
            types.pointer(actual).payload != pointee ||
            (target->kind == K::Store &&
             types.pointer(actual).mode != ParameterMode::Mut))
          return std::nullopt;
        continue;
      } else if ((target->kind == K::Extract && i == 1) ||
                 (target->kind == K::Insert && i == 2))
        expected = Type::I32;
      if (actual != expected)
        return std::nullopt;
    }
    return signature(target->kind == K::Store     ? Type::Unit
                     : target->kind == K::Extract ? target->element
                                                  : argument,
                     Shape::Value, true);
  }
  if (operation == "mem.forget")
    return operands.size() == 1 ? signature(Type::Unit) : std::nullopt;
  if (operation == "mem.drop")
    return operands.size() == 1 && types.isSized(operands[0])
               ? signature(Type::Unit)
               : std::nullopt;
  if (operation == "hint.black_box")
    return operands.size() == 1 && operands[0] == argument ? signature(argument)
                                                           : std::nullopt;
  for (auto operand : operands)
    if (containsVarArgs(types, operand))
      return std::nullopt;
  if (operation == "intrinsics.abort")
    return operands.empty() ? signature(Type::Never) : std::nullopt;
  if (operation.starts_with("coroutine.")) {
    bool state = types.isProduct(argument) &&
                 types.product(argument).kind == AggregateKind::Coroutine;
    if (operation == "coroutine.suspend")
      return operands.empty() ? signature(Type::Unit) : std::nullopt;
    if (operation == "coroutine.context")
      return operands.empty() ? signature(Type::U8, Shape::PointerMut)
                              : std::nullopt;
    if (operation == "coroutine.start")
      return state && operands.size() == 1 &&
                     operands[0] == types.product(argument).components[1]
                 ? signature(argument, Shape::Value, true)
                 : std::nullopt;
    if (operation == "coroutine.resume")
      return state && operands.size() == 2 && types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut &&
                     types.isPointer(operands[1]) &&
                     types.pointer(operands[1]).payload == Type::U8 &&
                     types.pointer(operands[1]).mode == ParameterMode::Mut
                 ? signature(types.product(argument).components[0],
                             Shape::Optional, true)
                 : std::nullopt;
    return std::nullopt;
  }
  if (operation == "intrinsics.panic_message")
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.isSlice(types.view(operands[0]).payload) &&
                   types.slice(types.view(operands[0]).payload).element ==
                       Type::U8
               ? signature(Type::Never)
               : std::nullopt;
  auto exclusive = [&](Type type) {
    return types.isView(type) && types.view(type).mode == ParameterMode::Mut &&
           types.view(type).payload == argument && types.contains(argument) &&
           types.isSized(argument);
  };
  if (operation == "mem.replace")
    return operands.size() == 2 && exclusive(operands[0]) &&
                   operands[1] == argument
               ? signature(argument)
               : std::nullopt;
  if (operation == "mem.swap")
    return operands.size() == 2 && exclusive(operands[0]) &&
                   operands[1] == operands[0]
               ? signature(Type::Unit)
               : std::nullopt;
  if (operation == "mem.size_of_val" || operation == "mem.align_of_val")
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.view(operands[0]).payload == argument &&
                   types.contains(argument) &&
                   (types.isSized(argument) ||
                    types.pointerMetadata(argument) != PointerMetadata::None)
               ? signature(Type::Usize)
               : std::nullopt;
  if (operation == "mem.zeroed")
    return operands.empty() && types.contains(argument) &&
                   types.isSized(argument)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  if (operation == "mem.transmute") {
    if (operands.size() != 1 || !types.contains(argument) ||
        !types.isSized(argument) || !types.isSized(operands[0]))
      return std::nullopt;
    auto source = objectLayout(types, operands[0]);
    auto target = objectLayout(types, argument);
    return argument == operands[0] ||
                   (source && target && source->size == target->size)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  }
  if (operation.starts_with("atomic.")) {
    auto ordering = [&](Type type) {
      return types.isProduct(type) &&
             types.product(type).kind == AggregateKind::Ordering;
    };
    auto method = operation.substr(7);
    if (method == "fence" || method == "compiler_fence")
      return operands.size() == 1 && ordering(operands[0])
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (method == "new")
      return types.isProduct(argument) &&
                     types.product(argument).kind == AggregateKind::Atomic &&
                     operands.size() == 1 &&
                     operands[0] == types.product(argument).components[0]
                 ? signature(argument)
                 : std::nullopt;
    bool raw = method.starts_with("raw_");
    if (raw)
      method.remove_prefix(4);
    if (operands.empty())
      return std::nullopt;
    Type payload = Type::Unknown, wrapper = Type::Unknown;
    if (raw && types.isPointer(operands[0]))
      payload = types.pointer(operands[0]).payload;
    else {
      wrapper = types.isView(operands[0]) ? types.view(operands[0]).payload
                                          : operands[0];
      if (!types.isProduct(wrapper) ||
          types.product(wrapper).kind != AggregateKind::Atomic)
        return std::nullopt;
      payload = types.product(wrapper).components[0];
    }
    bool scalar =
        isInteger(payload) || payload == Type::Bool || types.isPointer(payload);
    if (!scalar || (isInteger(payload) && integerWidth(payload) > 64))
      return std::nullopt;
    if (method == "into_inner")
      return !raw && operands.size() == 1 && operands[0] == wrapper
                 ? signature(payload)
                 : std::nullopt;
    if (method == "as_ptr")
      return !raw && operands.size() == 1
                 ? signature(payload, Shape::PointerMut)
                 : std::nullopt;
    if (method == "get_mut")
      return !raw && operands.size() == 1 && types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (!raw && !types.isView(operands[0]))
      return std::nullopt;
    if (raw && method != "load" &&
        types.pointer(operands[0]).mode != ParameterMode::Mut)
      return std::nullopt;
    if (method == "load")
      return operands.size() == 2 && ordering(operands[1])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    if (method == "store")
      return operands.size() == 3 && operands[1] == payload &&
                     ordering(operands[2])
                 ? signature(Type::Unit, Shape::Value, raw)
                 : std::nullopt;
    if (method == "compare_exchange" || method == "compare_exchange_weak")
      return operands.size() == 5 && operands[1] == payload &&
                     operands[2] == payload && ordering(operands[3]) &&
                     ordering(operands[4])
                 ? signature(payload, Shape::Outcome, raw)
                 : std::nullopt;
    if (method == "fetch_not")
      return !raw && payload == Type::Bool && operands.size() == 2 &&
                     ordering(operands[1])
                 ? signature(payload)
                 : std::nullopt;
    bool pointerMask = types.isPointer(payload) &&
                       (method == "fetch_and" || method == "fetch_or" ||
                        method == "fetch_xor");
    if (method == "swap" || method == "fetch_and" || method == "fetch_or" ||
        method == "fetch_xor" || method == "fetch_nand" ||
        ((method == "fetch_add" || method == "fetch_sub" ||
          method == "fetch_min" || method == "fetch_max") &&
         isInteger(payload)))
      return operands.size() == 3 &&
                     operands[1] == (pointerMask ? Type::Usize : payload) &&
                     ordering(operands[2])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    if (method == "fetch_ptr_add" || method == "fetch_ptr_sub" ||
        method == "fetch_byte_add" || method == "fetch_byte_sub")
      return types.isPointer(payload) && operands.size() == 3 &&
                     operands[1] == Type::Usize && ordering(operands[2])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    return std::nullopt;
  }
  if (operation == "pin.inline")
    return operands.size() == 1 && types.isSized(operands[0])
               ? signature(operands[0], Shape::PinMut)
               : std::nullopt;
  if (operation == "pin.new" || operation == "pin.new_unchecked")
    return operands.size() == 1 && types.isView(operands[0]) &&
                   (operation == "pin.new_unchecked" ||
                    unpin(types.view(operands[0]).payload))
               ? signature(types.view(operands[0]).payload,
                           types.view(operands[0]).mode == ParameterMode::Mut
                               ? Shape::PinMut
                               : Shape::PinRead,
                           operation == "pin.new_unchecked")
               : std::nullopt;
  if (operation.starts_with("pin.")) {
    auto method = operation.substr(4);
    if (!types.isProduct(argument) ||
        types.product(argument).kind != AggregateKind::Pin)
      return std::nullopt;
    auto view = types.product(argument).components[0];
    auto payload = types.view(view).payload;
    if (method == "into_inner" || method == "into_inner_unchecked")
      return operands.size() == 1 && operands[0] == argument &&
                     (method == "into_inner_unchecked" || unpin(payload))
                 ? signature(view, Shape::Value,
                             method == "into_inner_unchecked")
                 : std::nullopt;
    if (operands.size() != 1 || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    if (method == "as_ref")
      return signature(payload, Shape::PinRead);
    if (method == "get_ref")
      return signature(payload, Shape::ViewRead);
    bool exclusive = types.view(view).mode == ParameterMode::Mut &&
                     types.view(operands[0]).mode == ParameterMode::Mut;
    if (method.starts_with("project.") && types.isProduct(payload) &&
        !types.isSum(payload)) {
      const auto &record = types.product(payload);
      auto name = method.substr(8);
      for (std::size_t field = 0; field < record.fields.size(); ++field)
        if (record.fields[field].name == name) {
          if (record.layout.packing) {
            auto owner = objectLayout(types, payload);
            auto member = objectLayout(types, record.fields[field].type);
            if (!owner || !member || owner->alignment < member->alignment ||
                owner->fields[field] % member->alignment != 0)
              return std::nullopt;
          }
          bool pinned = std::find(record.layout.pinnedFields.begin(),
                                  record.layout.pinnedFields.end(),
                                  field) != record.layout.pinnedFields.end();
          return signature(record.fields[field].type,
                           pinned
                               ? (exclusive ? Shape::PinMut : Shape::PinRead)
                               : (exclusive ? Shape::ViewMut : Shape::ViewRead),
                           record.layout.unionType);
        }
    }
    if (method == "as_mut")
      return exclusive ? signature(payload, Shape::PinMut) : std::nullopt;
    if (method == "get_mut" || method == "get_unchecked_mut")
      return exclusive && (method == "get_unchecked_mut" || unpin(payload))
                 ? signature(payload, Shape::ViewMut,
                             method == "get_unchecked_mut")
                 : std::nullopt;
    return std::nullopt;
  }
  if (operation.starts_with("storage.")) {
    auto method = operation.substr(8);
    if (!types.isProduct(argument))
      return std::nullopt;
    const auto &storage = types.product(argument);
    if (storage.kind != AggregateKind::Uninit &&
        storage.kind != AggregateKind::ManualDrop &&
        storage.kind != AggregateKind::UnsafeCell)
      return std::nullopt;
    auto payload = storage.components[0];
    if (method == "new")
      return operands.size() == 1 && operands[0] == payload &&
                     types.isSized(payload)
                 ? signature(argument)
                 : std::nullopt;
    if (method == "uninit" || method == "zeroed")
      return operands.empty() && storage.kind == AggregateKind::Uninit
                 ? signature(argument)
                 : std::nullopt;
    if (method == "assume_init" || method == "into_inner")
      return operands.size() == 1 && operands[0] == argument &&
                     (method == "into_inner"
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::Value, method == "assume_init")
                 : std::nullopt;
    if (operands.empty() || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    bool exclusive = types.view(operands[0]).mode == ParameterMode::Mut;
    if (method == "drop" || method == "assume_init_drop")
      return storage.kind == (method == "drop" ? AggregateKind::ManualDrop
                                               : AggregateKind::Uninit) &&
                     exclusive && operands.size() == 1
                 ? signature(Type::Unit, Shape::Value, true)
                 : std::nullopt;
    if (method == "take" || method == "assume_init_read")
      return operands.size() == 1 &&
                     (method == "take"
                          ? storage.kind == AggregateKind::ManualDrop &&
                                exclusive
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::Value, true)
                 : std::nullopt;
    if (method == "write")
      return storage.kind == AggregateKind::Uninit && operands.size() == 2 &&
                     exclusive && operands[1] == payload
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (method == "as_ptr")
      return operands.size() == 1 ? signature(payload, Shape::PointerRead)
                                  : std::nullopt;
    if (method == "as_mut_ptr" || method == "get")
      return operands.size() == 1 &&
                     (method == "get"
                          ? storage.kind == AggregateKind::UnsafeCell
                          : exclusive)
                 ? signature(payload, Shape::PointerMut)
                 : std::nullopt;
    if (method == "get_ref" || method == "assume_init_ref")
      return operands.size() == 1 &&
                     (method == "get_ref"
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::ViewRead,
                             method == "assume_init_ref" ||
                                 storage.kind == AggregateKind::UnsafeCell)
                 : std::nullopt;
    if (method == "get_mut" || method == "assume_init_mut")
      return operands.size() == 1 && exclusive &&
                     (method == "get_mut"
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::ViewMut,
                             method == "assume_init_mut")
                 : std::nullopt;
    return std::nullopt;
  }
  if (operation == "size_of" || operation == "align_of" ||
      operation == "needs_drop" || operation == "type_id") {
    if (!operands.empty() || !types.contains(argument) ||
        (operation != "type_id" && !types.isSized(argument)))
      return std::nullopt;
    return signature(operation == "needs_drop" ? Type::Bool
                     : operation == "type_id"  ? Type::U64
                                               : Type::Usize);
  }
  if (operation == "ptr.null" || operation == "ptr.null_mut" ||
      operation == "ptr.without_provenance" ||
      operation == "ptr.with_exposed_provenance") {
    bool address = operation != "ptr.null" && operation != "ptr.null_mut";
    if (!types.contains(argument) || !types.isSized(argument) ||
        operands.size() != (address ? 1u : 0u) ||
        (address && operands[0] != Type::Usize))
      return std::nullopt;
    return signature(argument, operation == "ptr.null_mut"
                                   ? Shape::PointerMut
                                   : Shape::PointerRead);
  }
  if (operation == "ptr.from_ref" || operation == "ptr.from_mut") {
    if (operands.size() != 1 || !types.isView(operands[0]) ||
        (operation == "ptr.from_mut" &&
         types.view(operands[0]).mode != ParameterMode::Mut))
      return std::nullopt;
    return signature(types.view(operands[0]).payload,
                     operation == "ptr.from_mut" ? Shape::PointerMut
                                                 : Shape::PointerRead);
  }
  if (operation.starts_with("numeric.")) {
    auto method = operation.substr(8);
    bool fromBytes = method == "from_be_bytes" || method == "from_le_bytes" ||
                     method == "from_ne_bytes";
    if (fromBytes) {
      if (operands.size() != 1 || !isNumeric(argument) ||
          !types.isProduct(operands[0]) ||
          types.product(operands[0]).kind != AggregateKind::Array ||
          types.product(operands[0]).components.empty() ||
          types.product(operands[0]).components[0] != Type::U8 ||
          types.arrayLength(operands[0]) !=
              std::optional<std::uint64_t>{
                  (isInteger(argument)
                       ? integerWidth(argument, types.targetPointerBits())
                   : argument == Type::F32 ? 32u
                                           : 64u) /
                  8u})
        return std::nullopt;
      return signature(argument);
    }
    if (operands.empty())
      return std::nullopt;
    bool makeAscii =
        method == "make_ascii_lowercase" || method == "make_ascii_uppercase";
    auto self = operands[0];
    if (types.isView(self)) {
      if (!makeAscii || types.view(self).mode != ParameterMode::Mut ||
          types.view(self).payload != Type::U8)
        return std::nullopt;
      self = types.view(self).payload;
    } else if (!isNumeric(self))
      return std::nullopt;
    if (method == "checked_cast")
      return operands.size() == 1 && isInteger(argument)
                 ? signature(argument, Shape::Optional)
                 : std::nullopt;
    if (method == "to_int_unchecked")
      return operands.size() == 1 && isFloating(self) && isInteger(argument)
                 ? signature(argument, Shape::Value, true)
                 : std::nullopt;
    bool toBytes = method == "to_be_bytes" || method == "to_le_bytes" ||
                   method == "to_ne_bytes";
    if (argument != Type::Unknown && method != "from_bits" && !toBytes &&
        method != "sin_cos" && self != argument)
      return std::nullopt;
    if (method == "sin_cos")
      return operands.size() == 1 && isFloating(self) &&
                     types.isProduct(argument) &&
                     types.product(argument).kind == AggregateKind::Tuple &&
                     types.product(argument).components ==
                         std::vector<Type>{self, self}
                 ? signature(argument)
                 : std::nullopt;
    if (method == "to_bits") {
      if (operands.size() != 1 || !isFloating(self))
        return std::nullopt;
      return signature(self == Type::F32 ? Type::U32 : Type::U64);
    }
    if (method == "from_bits") {
      if (operands.size() != 1 || !isFloating(argument) ||
          self != (argument == Type::F32 ? Type::U32 : Type::U64))
        return std::nullopt;
      return signature(argument);
    }
    if (method == "to_be_bytes" || method == "to_le_bytes" ||
        method == "to_ne_bytes") {
      if (operands.size() != 1 || !types.isProduct(argument) ||
          types.product(argument).kind != AggregateKind::Array ||
          types.product(argument).components.empty() ||
          types.product(argument).components[0] != Type::U8)
        return std::nullopt;
      auto width = isInteger(self)
                       ? integerWidth(self, types.targetPointerBits())
                   : self == Type::F32 ? 32u
                                       : 64u;
      return types.arrayLength(argument) ==
                     std::optional<std::uint64_t>{width / 8u}
                 ? signature(argument)
                 : std::nullopt;
    }
    if (method == "to_be" || method == "to_le" || method == "from_be" ||
        method == "from_le")
      return operands.size() == 1 && isInteger(self) ? signature(self)
                                                     : std::nullopt;
    if (isFloating(self)) {
      bool predicate = method == "is_nan" || method == "is_infinite" ||
                       method == "is_finite" || method == "is_sign_negative" ||
                       method == "is_sign_positive" ||
                       method == "is_subnormal" || method == "is_normal";
      bool unary = predicate || method == "abs" || method == "sqrt" ||
                   method == "floor" || method == "ceil" || method == "trunc" ||
                   method == "round" || method == "round_ties_even" ||
                   method == "sin" || method == "cos" || method == "tan" ||
                   method == "asin" || method == "acos" || method == "atan" ||
                   method == "sinh" || method == "cosh" || method == "tanh" ||
                   method == "asinh" || method == "acosh" ||
                   method == "atanh" || method == "exp" || method == "exp2" ||
                   method == "exp_m1" || method == "ln" || method == "ln_1p" ||
                   method == "log2" || method == "log10" || method == "cbrt" ||
                   method == "fract" || method == "recip" ||
                   method == "signum" || method == "to_degrees" ||
                   method == "to_radians" || method == "next_up" ||
                   method == "next_down";
      bool clamp = method == "clamp";
      bool binary = method == "copysign" || method == "atan2" ||
                    method == "log" || method == "powf" || method == "hypot" ||
                    method == "div_euclid" || method == "rem_euclid" ||
                    method == "midpoint" || method == "min" || method == "max";
      auto count = method == "mul_add" ? 3u
                   : method == "powi"  ? 2u
                   : clamp             ? 3u
                   : binary            ? 2u
                                       : 1u;
      bool powi = method == "powi";
      if ((!unary && count == 1) || operands.size() != count ||
          (powi ? operands[1] != Type::I32
                : !std::all_of(operands.begin(), operands.end(),
                               [&](Type type) { return type == self; })))
        return std::nullopt;
      return signature(predicate ? Type::Bool : self);
    }
    if (method == "count_ones" || method == "count_zeros" ||
        method == "leading_zeros" || method == "trailing_zeros" ||
        method == "leading_ones" || method == "trailing_ones" ||
        method == "swap_bytes" || method == "reverse_bits") {
      if (operands.size() != 1)
        return std::nullopt;
      return signature(method == "swap_bytes" || method == "reverse_bits"
                           ? self
                           : Type::U32);
    }
    if (method == "rotate_left" || method == "rotate_right") {
      if (operands.size() != 2 || operands[1] != Type::U32)
        return std::nullopt;
      return signature(self);
    }
    if (!isInteger(self))
      return std::nullopt;
    auto unsignedType = [&] {
      if (self == Type::I8 || self == Type::U8)
        return Type::U8;
      if (self == Type::I16 || self == Type::U16)
        return Type::U16;
      if (self == Type::I32 || self == Type::U32)
        return Type::U32;
      if (self == Type::I64 || self == Type::U64)
        return Type::U64;
      if (self == Type::I128 || self == Type::U128)
        return Type::U128;
      return Type::Usize;
    };
    auto signedType = [&] {
      if (self == Type::I8 || self == Type::U8)
        return Type::I8;
      if (self == Type::I16 || self == Type::U16)
        return Type::I16;
      if (self == Type::I32 || self == Type::U32)
        return Type::I32;
      if (self == Type::I64 || self == Type::U64)
        return Type::I64;
      if (self == Type::I128 || self == Type::U128)
        return Type::I128;
      return Type::Isize;
    };
    if (method == "is_positive" || method == "is_negative" ||
        method == "signum")
      return operands.size() == 1 && isSignedInteger(self)
                 ? signature(method == "signum" ? self : Type::Bool)
                 : std::nullopt;
    if (method == "is_power_of_two")
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(Type::Bool)
                 : std::nullopt;
    if (method == "bit_width")
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(Type::U32)
                 : std::nullopt;
    if (method == "highest_one" || method == "lowest_one")
      return operands.size() == 1 ? signature(Type::U32, Shape::Optional)
                                  : std::nullopt;
    if (method == "isolate_highest_one" || method == "isolate_lowest_one")
      return operands.size() == 1 ? signature(self) : std::nullopt;
    if (method == "carrying_add" || method == "borrowing_sub")
      return operands.size() == 3 && !isSignedInteger(self) &&
                     operands[1] == self && operands[2] == Type::Bool
                 ? signature(self, Shape::Overflow)
                 : std::nullopt;
    if (method == "carrying_mul" || method == "carrying_mul_add")
      return operands.size() == (method == "carrying_mul" ? 3u : 4u) &&
                     !isSignedInteger(self) &&
                     std::all_of(operands.begin(), operands.end(),
                                 [&](Type type) { return type == self; })
                 ? signature(self, Shape::Pair)
                 : std::nullopt;
    if (method == "checked_signed_diff")
      return operands.size() == 2 && !isSignedInteger(self) &&
                     operands[1] == self
                 ? signature(signedType(), Shape::Optional)
                 : std::nullopt;
    if (method == "ilog2" || method == "ilog10" || method == "checked_ilog2" ||
        method == "checked_ilog10")
      return operands.size() == 1
                 ? signature(Type::U32, method.starts_with("checked_")
                                            ? Shape::Optional
                                            : Shape::Value)
                 : std::nullopt;
    if (method == "ilog" || method == "checked_ilog")
      return operands.size() == 2 && operands[1] == self
                 ? signature(Type::U32, method.starts_with("checked_")
                                            ? Shape::Optional
                                            : Shape::Value)
                 : std::nullopt;
    if (method == "isqrt" || method == "checked_isqrt")
      return operands.size() == 1
                 ? signature(self, method.starts_with("checked_")
                                       ? Shape::Optional
                                       : Shape::Value)
                 : std::nullopt;
    if (method == "next_power_of_two" || method == "checked_next_power_of_two")
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(self, method.starts_with("checked_")
                                       ? Shape::Optional
                                       : Shape::Value)
                 : std::nullopt;
    if (method == "div_ceil" || method == "next_multiple_of" ||
        method == "checked_next_multiple_of" || method == "is_multiple_of")
      return operands.size() == 2 && operands[1] == self &&
                     !isSignedInteger(self)
                 ? signature(method == "is_multiple_of" ? Type::Bool : self,
                             method.starts_with("checked_") ? Shape::Optional
                                                            : Shape::Value)
                 : std::nullopt;
    if (method == "midpoint")
      return operands.size() == 2 && operands[1] == self ? signature(self)
                                                         : std::nullopt;
    if (method == "unbounded_shl" || method == "unbounded_shr")
      return operands.size() == 2 && operands[1] == Type::U32 ? signature(self)
                                                              : std::nullopt;
    if (method.starts_with("unchecked_")) {
      auto unchecked = method.substr(10);
      bool unary = unchecked == "neg";
      bool shift = unchecked == "shl" || unchecked == "shr";
      if (unchecked != "add" && unchecked != "sub" && unchecked != "mul" &&
          !unary && !shift)
        return std::nullopt;
      return operands.size() == (unary ? 1u : 2u) &&
                     (unary || operands[1] == (shift ? Type::U32 : self))
                 ? signature(self, Shape::Value, true)
                 : std::nullopt;
    }
    if (method == "cast_signed" || method == "cast_unsigned")
      return operands.size() == 1 &&
                     ((method == "cast_signed" && !isSignedInteger(self)) ||
                      (method == "cast_unsigned" && isSignedInteger(self)))
                 ? signature(method == "cast_signed" ? signedType()
                                                     : unsignedType())
                 : std::nullopt;
    if (method == "is_ascii" || method == "is_ascii_alphabetic" ||
        method == "is_ascii_alphanumeric" || method == "is_ascii_control" ||
        method == "is_ascii_digit" || method == "is_ascii_graphic" ||
        method == "is_ascii_hexdigit" || method == "is_ascii_lowercase" ||
        method == "is_ascii_punctuation" || method == "is_ascii_uppercase" ||
        method == "is_ascii_whitespace")
      return self == Type::U8 && operands.size() == 1 ? signature(Type::Bool)
                                                      : std::nullopt;
    if (method == "to_ascii_lowercase" || method == "to_ascii_uppercase")
      return self == Type::U8 && operands.size() == 1 ? signature(Type::U8)
                                                      : std::nullopt;
    if (makeAscii)
      return self == Type::U8 && operands.size() == 1 &&
                     types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (method == "eq_ignore_ascii_case")
      return self == Type::U8 && operands.size() == 2 && operands[1] == Type::U8
                 ? signature(Type::Bool)
                 : std::nullopt;
    if (method == "unsigned_abs")
      return operands.size() == 1 && isSignedInteger(self)
                 ? signature(unsignedType())
                 : std::nullopt;
    if (method == "abs_diff")
      return operands.size() == 2 && operands[1] == self
                 ? signature(unsignedType())
                 : std::nullopt;
    if (method == "pow" || method == "checked_pow" ||
        method == "wrapping_pow" || method == "overflowing_pow" ||
        method == "saturating_pow" || method == "strict_pow") {
      auto shape = method == "checked_pow"       ? Shape::Optional
                   : method == "overflowing_pow" ? Shape::Overflow
                                                 : Shape::Value;
      return operands.size() == 2 && operands[1] == Type::U32
                 ? signature(self, shape)
                 : std::nullopt;
    }
    bool strict = method.starts_with("strict_");
    if (strict) {
      method.remove_prefix(7);
      if (method.starts_with("checked_") || method.starts_with("wrapping_") ||
          method.starts_with("overflowing_") ||
          method.starts_with("saturating_"))
        return std::nullopt;
    }
    Shape shape = Shape::Value;
    if (method.starts_with("wrapping_"))
      method.remove_prefix(9);
    else if (method.starts_with("checked_")) {
      method.remove_prefix(8);
      shape = Shape::Optional;
    } else if (method.starts_with("overflowing_")) {
      method.remove_prefix(12);
      shape = Shape::Overflow;
    } else if (method.starts_with("saturating_"))
      method.remove_prefix(11);
    else if (!strict && !method.ends_with("_signed") &&
             !method.ends_with("_unsigned") && method != "div_euclid" &&
             method != "rem_euclid" && method != "abs")
      return std::nullopt;
    bool mixedSigned = method.ends_with("_signed");
    bool mixedUnsigned = method.ends_with("_unsigned");
    if (mixedSigned || mixedUnsigned) {
      method.remove_suffix(mixedSigned ? 7 : 9);
      bool validOperation = method == "add" || method == "sub";
      bool validSign =
          mixedSigned ? !isSignedInteger(self) : isSignedInteger(self);
      auto expected = mixedSigned ? signedType() : unsignedType();
      return validOperation && validSign && operands.size() == 2 &&
                     operands[1] == expected
                 ? signature(self, shape)
                 : std::nullopt;
    }
    bool unary = method == "neg" || method == "abs";
    bool shift = method == "shl" || method == "shr";
    if (method != "add" && method != "sub" && method != "mul" &&
        method != "div" && method != "rem" && !unary && !shift &&
        method != "div_euclid" && method != "rem_euclid")
      return std::nullopt;
    if (method == "abs" && !isSignedInteger(self))
      return std::nullopt;
    if (operands.size() != (unary ? 1u : 2u) ||
        (!unary && operands[1] != (shift ? Type::U32 : self)))
      return std::nullopt;
    if (operation.starts_with("numeric.saturating_") &&
        (shift || method == "rem"))
      return std::nullopt;
    if (operation.starts_with("numeric.saturating_") &&
        (method == "div_euclid" || method == "rem_euclid"))
      return std::nullopt;
    return signature(self, shape);
  }
  if (!operation.starts_with("ptr.") || operands.empty() ||
      !types.isPointer(operands[0]))
    return std::nullopt;
  auto pointer = operands[0];
  auto descriptor = types.pointer(pointer);
  auto method = operation.substr(4);
  if (method == "copy" || method == "copy_nonoverlapping" || method == "swap" ||
      method == "swap_nonoverlapping") {
    bool swap = method.starts_with("swap");
    auto count = method == "swap" ? 2u : 3u;
    return operands.size() == count && types.isSized(descriptor.payload) &&
                   (!swap || descriptor.mode == ParameterMode::Mut) &&
                   types.isPointer(operands[1]) &&
                   types.pointer(operands[1]).mode == ParameterMode::Mut &&
                   types.pointer(operands[1]).payload == descriptor.payload &&
                   (count == 2 || operands[2] == Type::Usize)
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  }
  if (method == "write_bytes")
    return operands.size() == 3 && descriptor.mode == ParameterMode::Mut &&
                   types.isSized(descriptor.payload) &&
                   operands[1] == Type::U8 && operands[2] == Type::Usize
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  if (method == "replace")
    return operands.size() == 2 && descriptor.mode == ParameterMode::Mut &&
                   types.isSized(descriptor.payload) &&
                   operands[1] == descriptor.payload
               ? signature(descriptor.payload, Shape::Value, true)
               : std::nullopt;
  if (method == "offset_from" || method == "offset_from_unsigned" ||
      method == "byte_offset_from" || method == "byte_offset_from_unsigned")
    return operands.size() == 2 && types.isPointer(operands[1]) &&
                   types.pointer(operands[1]).payload == descriptor.payload &&
                   (method.starts_with("byte_") ||
                    types.isSized(descriptor.payload))
               ? signature(method.ends_with("_unsigned") ? Type::Usize
                                                         : Type::Isize,
                           Shape::Value, true)
               : std::nullopt;
  if (method == "drop_in_place")
    return operands.size() == 1 && descriptor.mode == ParameterMode::Mut &&
                   (types.isSized(descriptor.payload) ||
                    (types.isParameter(descriptor.payload) &&
                     !types.isSized(descriptor.payload)) ||
                    (types.isSlice(descriptor.payload) &&
                     types.isSized(types.slice(descriptor.payload).element)) ||
                    types.isErased(descriptor.payload))
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  if (method == "is_null" || method == "addr" ||
      method == "expose_provenance") {
    if (operands.size() != 1)
      return std::nullopt;
    return signature(method == "is_null" ? Type::Bool : Type::Usize);
  }
  if (method == "cast" || method == "cast_mut" || method == "cast_const") {
    if (operands.size() != 1 || (method == "cast" && !types.isSized(argument)))
      return std::nullopt;
    return signature(
        method == "cast" ? argument : descriptor.payload,
        method == "cast_mut" ||
                (method == "cast" && descriptor.mode == ParameterMode::Mut)
            ? Shape::PointerMut
            : Shape::PointerRead);
  }
  if (method == "with_addr") {
    if (operands.size() != 2 || operands[1] != Type::Usize)
      return std::nullopt;
    return signature(pointer);
  }
  if (method == "read" || method == "read_volatile" ||
      method == "read_unaligned") {
    if (operands.size() != 1 || !types.isSized(descriptor.payload))
      return std::nullopt;
    return signature(descriptor.payload, Shape::Value, true);
  }
  if (method == "write" || method == "write_volatile" ||
      method == "write_unaligned") {
    if (operands.size() != 2 || descriptor.mode != ParameterMode::Mut ||
        operands[1] != descriptor.payload || !types.isSized(descriptor.payload))
      return std::nullopt;
    return signature(Type::Unit, Shape::Value, true);
  }
  bool wrapping = method.starts_with("wrapping_");
  if (wrapping)
    method.remove_prefix(9);
  bool bytes = method.starts_with("byte_");
  if (bytes)
    method.remove_prefix(5);
  if (method != "add" && method != "sub" && method != "offset")
    return std::nullopt;
  if (operands.size() != 2 || (!bytes && !types.isSized(descriptor.payload)) ||
      operands[1] != (method == "offset" ? Type::Isize : Type::Usize))
    return std::nullopt;
  return signature(pointer, Shape::Value, !wrapping);
}
bool machineResultMatches(const TypeStore &types,
                          const MachineSignature &signature, Type result) {
  using Shape = MachineSignature::Shape;
  if (signature.shape == Shape::Ref || signature.shape == Shape::RefMut ||
      signature.shape == Shape::TryRef || signature.shape == Shape::TryRefMut) {
    bool exclusive =
        signature.shape == Shape::RefMut || signature.shape == Shape::TryRefMut;
    bool fallible =
        signature.shape == Shape::TryRef || signature.shape == Shape::TryRefMut;
    if (fallible) {
      if (!types.isProduct(result) ||
          types.product(result).kind != AggregateKind::Outcome ||
          !types.isProduct(types.product(result).components[1]) ||
          types.product(types.product(result).components[1]).kind !=
              (exclusive ? AggregateKind::BorrowMutError
                         : AggregateKind::BorrowError))
        return false;
      result = types.product(result).components[0];
    }
    return types.isProduct(result) &&
           types.product(result).kind ==
               (exclusive ? AggregateKind::RefMut : AggregateKind::Ref) &&
           types.isView(types.product(result).components[0]) &&
           types.view(types.product(result).components[0]).mode ==
               ParameterMode::Read &&
           types.view(types.product(result).components[0]).payload ==
               signature.value;
  }
  if (signature.shape == Shape::Outcome)
    return types.isProduct(result) &&
           types.product(result).kind == AggregateKind::Outcome &&
           types.product(result).components ==
               std::vector<Type>{signature.value, signature.value};
  if (signature.shape == Shape::PinRead || signature.shape == Shape::PinMut)
    return types.isProduct(result) &&
           types.product(result).kind == AggregateKind::Pin &&
           types.isView(types.product(result).components[0]) &&
           types.view(types.product(result).components[0]).payload ==
               signature.value &&
           types.view(types.product(result).components[0]).mode ==
               (signature.shape == Shape::PinMut ? ParameterMode::Mut
                                                 : ParameterMode::Read);
  if (signature.shape == Shape::Value)
    return result == signature.value;
  if (signature.shape == Shape::PointerRead ||
      signature.shape == Shape::PointerMut)
    return types.isPointer(result) &&
           types.pointer(result).payload == signature.value &&
           types.pointer(result).mode == (signature.shape == Shape::PointerMut
                                              ? ParameterMode::Mut
                                              : ParameterMode::Read);
  if (signature.shape == Shape::ViewRead || signature.shape == Shape::ViewMut)
    return types.isView(result) &&
           types.view(result).payload == signature.value &&
           types.view(result).mode == (signature.shape == Shape::ViewMut
                                           ? ParameterMode::Mut
                                           : ParameterMode::Read);
  if (!types.isProduct(result))
    return false;
  const auto &record = types.product(result);
  if (signature.shape == Shape::Optional)
    return record.kind == AggregateKind::Optional &&
           record.components == std::vector<Type>{signature.value};
  return record.kind == AggregateKind::Tuple &&
         record.components ==
             std::vector<Type>{signature.value, signature.shape == Shape::Pair
                                                    ? signature.value
                                                    : Type::Bool};
}
} // namespace mettle
