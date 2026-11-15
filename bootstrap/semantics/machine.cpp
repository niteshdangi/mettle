#include "types/machine.h"
#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
std::optional<int> Checker::machineCall(Node &call, bool reachable,
                                        int receiver) {
  auto &callee = *call.children[0];
  std::string operation;
  Type argument = Type::Unknown;
  auto storageKind = AggregateKind::Product;
  unsigned dereferences = 0;
  Type self = receiver >= 0 ? inference.value(receiver) : Type::Unknown;
  while (checked.types->isView(self)) {
    self = checked.types->view(self).payload;
    ++dereferences;
  }
  if (receiver >= 0 && checked.types->isSlice(self) && callee.text == "len" &&
      !callee.flag) {
    if (call.children.size() != 1 || !callee.genericArguments.empty() ||
        !callee.ownerGenericArguments.empty()) {
      error("type", call.span, "slice len requires no arguments");
      return inference.fresh(Type::Usize);
    }
    facts(call).machineOperation = "slice.len";
    facts(call).dereferences = dereferences;
    facts(call).method = true;
    facts(call).machineBorrowModes = {ParameterMode::Read};
    facts(call).callParameterTypes = {
        checked.types->viewType(self, ParameterMode::Read)};
    return inference.fresh(Type::Usize);
  }
  if (receiver >= 0) {
    if (isNumeric(self))
      operation = "numeric." + callee.text;
    else if (checked.types->isPointer(self))
      operation = "ptr." + callee.text;
    else if (checked.types->isProduct(self) &&
             checked.types->product(self).kind == AggregateKind::VarArgs) {
      if (callee.text != "arg" && callee.text != "copy" && callee.text != "end")
        return std::nullopt;
      operation = "va." + callee.text;
    } else if (checked.types->isProduct(self) &&
               (checked.types->product(self).kind == AggregateKind::Cell ||
                checked.types->product(self).kind == AggregateKind::RefCell ||
                checked.types->product(self).kind == AggregateKind::Ref ||
                checked.types->product(self).kind == AggregateKind::RefMut)) {
      argument = self;
      operation = "cell." + callee.text;
    } else if (checked.types->isProduct(self) &&
               checked.types->product(self).kind == AggregateKind::Atomic) {
      argument = self;
      operation = "atomic." + callee.text;
    } else if (checked.types->isProduct(self) &&
               checked.types->product(self).kind == AggregateKind::Pin) {
      argument = self;
      operation = "pin." + callee.text;
      auto payload =
          checked.types->view(checked.types->product(self).components[0])
              .payload;
      if (checked.types->isProduct(payload)) {
        if (checked.types->isSum(payload) &&
            callee.text.starts_with("project_")) {
          error("feature", call.span,
                "pin projection of sum variants requires active-variant "
                "support");
          return inference.fresh();
        }
        const auto &record = checked.types->product(payload);
        for (std::size_t field = 0; field < record.fields.size(); ++field)
          if ("project_" + record.fields[field].name == callee.text) {
            visibleField(payload, field, call.span);
            facts(call).field = field;
            operation = "pin.project." + record.fields[field].name;
          }
      }
    } else if (checked.types->isProduct(self) &&
               (checked.types->product(self).kind == AggregateKind::Uninit ||
                checked.types->product(self).kind ==
                    AggregateKind::ManualDrop ||
                checked.types->product(self).kind ==
                    AggregateKind::UnsafeCell)) {
      storageKind = checked.types->product(self).kind;
      argument = self;
      operation = "storage." + callee.text;
    } else
      return std::nullopt;
  } else {
    auto separator = callee.text.rfind("::");
    if (separator == std::string::npos)
      return std::nullopt;
    auto owner = callee.text.substr(0, separator);
    if (auto resolved = checked.symbols->lookup(
            nameModule(callee.span, callee.context, true), owner,
            resolution::Namespace::Type, callee.span))
      owner = *resolved;
    auto name = callee.text.substr(separator + 2);
    if (owner.starts_with("core::sync::atomic::Atomic")) {
      TypeSyntax syntax;
      syntax.name = owner;
      syntax.arguments = callee.ownerGenericArguments;
      auto type = machineAnnotation(syntax, call.span, current->owner);
      if (!type || *type == Type::Unknown)
        return inference.fresh();
      argument = *type;
      operation = "atomic." + name;
    } else if (owner == "core::cell::Cell" || owner == "core::cell::RefCell") {
      storageKind = owner == "core::cell::Cell" ? AggregateKind::Cell
                                                : AggregateKind::RefCell;
      operation = "cell." + name;
      const auto &generics = callee.ownerGenericArguments.empty()
                                 ? callee.genericArguments
                                 : callee.ownerGenericArguments;
      if (generics.size() == 1 && generics[0].type)
        argument = checked.types->structural(
            storageKind,
            {annotation(*generics[0].type, call.span, current->owner)});
    } else if (owner == "core::sync::atomic" &&
               (name == "fence" || name == "compiler_fence"))
      operation = "atomic." + name;
    else if (owner == "core::intrinsics" && name.starts_with("atomic_"))
      operation = "atomic.raw_" + name.substr(7);
    else if (owner == "core::pin" && name == "pin")
      operation = "pin.inline";
    else if (owner == "core::pin::Pin" &&
             (name == "new" || name == "new_unchecked"))
      operation = "pin." + name;
    else if (owner == "core::mem::MaybeUninit" ||
             owner == "core::mem::ManuallyDrop" ||
             owner == "core::cell::UnsafeCell") {
      storageKind = owner == "core::mem::MaybeUninit" ? AggregateKind::Uninit
                    : owner == "core::mem::ManuallyDrop"
                        ? AggregateKind::ManualDrop
                        : AggregateKind::UnsafeCell;
      operation = "storage." + name;
      const auto &generics = callee.ownerGenericArguments.empty()
                                 ? callee.genericArguments
                                 : callee.ownerGenericArguments;
      if (generics.size() == 1 && generics[0].type)
        argument = checked.types->structural(
            storageKind,
            {annotation(*generics[0].type, call.span, current->owner)});
    } else if (owner == "core::mem" &&
               (name == "size_of" || name == "align_of" ||
                name == "needs_drop"))
      operation = name;
    else if (owner == "core::intrinsics" && name == "type_id")
      operation = "type_id";
    else if (owner == "core::intrinsics" && name == "fn_addr")
      operation = "intrinsics.fn_addr";
    else if (owner == "core::intrinsics" &&
             (name == "va_arg" || name == "va_copy"))
      operation = name == "va_arg" ? "va.next_arg" : "va.copy";
    else if (owner == "core::intrinsics" &&
             (name == "addr_of" || name == "addr_of_mut" ||
              name == "offset_of"))
      operation = "intrinsics." + name;
    else if (owner == "core::mem" &&
             (name == "transmute" || name == "transmute_copy" ||
              name == "zeroed" || name == "forget" || name == "drop" ||
              name == "replace" || name == "swap" || name == "size_of_val" ||
              name == "align_of_val" || name == "size_of_val_raw" ||
              name == "align_of_val_raw"))
      operation = "mem." + name;
    else if (owner == "core::hint" &&
             (name == "black_box" || name == "spin_loop" ||
              name == "cold_path" || name == "assert_unchecked" ||
              name == "select_unpredictable" ||
              name == "unreachable_unchecked"))
      operation = "hint." + name;
    else if (owner == "core::intrinsics" && name == "abort")
      operation = "intrinsics.abort";
    else if (owner == "core::intrinsics" && name == "panic_message")
      operation = "intrinsics.panic_message";
    else if (owner == "core::intrinsics" && name == "panic_fmt")
      operation = "intrinsics.panic_fmt";
    else if (owner == "core::intrinsics" && name == "type_name")
      operation = "intrinsics.type_name";
    else if (owner == "core::intrinsics" && name == "caller_location")
      operation = "intrinsics.caller_location";
    else if (owner == "core::intrinsics" && name == "variant_ordinal")
      operation = "intrinsics.variant_ordinal";
    else if (owner == "core::intrinsics" && name.starts_with("coroutine_"))
      operation = "coroutine." + name.substr(10);
    else if (owner == "core::ptr")
      operation = "ptr." + name;
    else if (isNumeric(primitiveOwner(
                 owner, nameModule(callee.span, callee.context, true),
                 callee.span))) {
      argument = primitiveOwner(
          owner, nameModule(callee.span, callee.context, true), callee.span);
      operation = "numeric." + name;
      if (operation == "numeric.to_int_unchecked") {
        self = argument;
        argument = Type::Unknown;
      }
    } else
      return std::nullopt;
  }
  if (operation == "intrinsics.addr_of" ||
      operation == "intrinsics.addr_of_mut") {
    if (call.children.size() != 2 || !callee.genericArguments.empty()) {
      error("type", call.span, "raw address requires one place argument");
      return inference.fresh();
    }
    auto &value = *call.children[1];
    auto *part = &value;
    while ((part->kind == Kind::Field || part->kind == Kind::Index ||
            part->kind == Kind::Group ||
            (part->kind == Kind::Unary && part->text == "*")) &&
           !part->children.empty()) {
      if (part->kind == Kind::Unary) {
        // Its operand is loaded as an ordinary value, so inner derefs stay unsafe.
        rawAddressDereferences.insert(part);
        break;
      }
      part = part->children[0].get();
    }
    if (value.kind != Kind::Name && value.kind != Kind::Field &&
        value.kind != Kind::Index && value.kind != Kind::Group &&
        !(value.kind == Kind::Unary && value.text == "*")) {
      error("type", value.span, "raw address requires a place");
      return inference.fresh();
    }
    auto variable = node(value, reachable);
    fields(false);
    bool exclusive = operation == "intrinsics.addr_of_mut";
    if (exclusive)
      requireMutablePlace(value);
    facts(call).machineOperation = operation;
    facts(call).machineType = inference.value(variable);
    facts(call).machineBorrowModes = {ParameterMode::Value};
    return inference.fresh(checked.types->pointerType(
        inference.value(variable),
        exclusive ? ParameterMode::Mut : ParameterMode::Read));
  }
  if (operation == "coroutine.suspend" || operation == "coroutine.context") {
    auto found = closureFunctions.find(current);
    if (found == closureFunctions.end() ||
        checked.closureBodies[found->second]->syntax->text != "coroutine")
      error("effects", call.span, "suspension outside an async body");
  }
  bool pointerView = operation == "ptr.as_ref" || operation == "ptr.as_mut" ||
                     operation == "ptr.as_ref_unchecked" ||
                     operation == "ptr.as_mut_unchecked";
  if (pointerView) {
    auto region = RegionId::Unspecified;
    if (!callee.genericArguments.empty()) {
      if (callee.genericArguments.size() != 1 ||
          callee.genericArguments[0].region.empty()) {
        error("type", call.span,
              "pointer view projection requires one region argument");
        return inference.fresh();
      }
      const auto &source = callee.genericArguments[0];
      region = regionReference(source.region, source.span);
    }
    if (checked.types->isPointer(self))
      argument = checked.types->viewType(
          checked.types->pointer(self).payload,
          operation == "ptr.as_mut" || operation == "ptr.as_mut_unchecked"
              ? ParameterMode::Mut
              : ParameterMode::Read,
          region);
  }
  bool pointerArray =
      operation == "ptr.as_array" || operation == "ptr.as_mut_array";
  if (pointerArray) {
    if (callee.genericArguments.size() != 1 ||
        !callee.genericArguments[0].region.empty()) {
      error("type", call.span,
            "array pointer projection requires one constant length argument");
      return inference.fresh();
    }
    auto count = genericArgument(callee.genericArguments[0],
                                 checked.types->constant(Type::Usize, 0));
    if (count == Type::Unknown)
      return inference.fresh();
    if (!isInteger(checked.types->parameter(count).valueType)) {
      error("type", call.span, "array length requires an integer constant");
      return inference.fresh();
    }
    if (auto value = checked.types->scalarConstantValue(count);
        value && (value->negative || value->magnitude[1])) {
      error("limit", call.span, "array length limit exceeded");
      return inference.fresh();
    }
    if (checked.types->isPointer(self)) {
      const auto &pointer = checked.types->pointer(self);
      if (checked.types->isSlice(pointer.payload))
        argument = checked.types->pointerType(
            checked.types->arrayType(
                checked.types->slice(pointer.payload).element, count),
            operation == "ptr.as_mut_array" ? ParameterMode::Mut
                                            : ParameterMode::Read);
    }
  }
  if (!pointerView && !pointerArray && !callee.genericArguments.empty() &&
      !operation.starts_with("atomic.") &&
      storageKind == AggregateKind::Product) {
    if (callee.genericArguments.size() != 1 ||
        !callee.genericArguments[0].type) {
      error("type", call.span,
            "primitive operation requires one type argument");
      return inference.fresh();
    }
    argument =
        annotation(*callee.genericArguments[0].type, call.span, current->owner);
  }
  if (argument == Type::Unknown && expectedTypes.contains(&call) &&
      checked.types->isPointer(expectedTypes.at(&call)))
    argument = checked.types->pointer(expectedTypes.at(&call)).payload;
  if (argument == Type::Unknown && expectedTypes.contains(&call) &&
      (operation == "mem.transmute" || operation == "mem.transmute_copy" ||
       operation == "mem.zeroed"))
    argument = expectedTypes.at(&call);
  if (operation == "intrinsics.offset_of") {
    if (call.children.size() != 2 || !checked.types->isProduct(argument)) {
      error("type", call.span,
            "offset_of requires a product type and field path");
      return inference.fresh();
    }
    std::vector<std::string> path;
    auto syntax = call.children[1].get();
    while (syntax->kind == Kind::Field && syntax->children.size() == 1) {
      path.push_back(syntax->text);
      syntax = syntax->children[0].get();
    }
    if ((syntax->kind != Kind::Name && syntax->kind != Kind::Integer) ||
        syntax->text.find("::") != std::string::npos) {
      error("type", call.span, "offset_of requires a field path");
      return inference.fresh();
    }
    path.push_back(syntax->text);
    std::reverse(path.begin(), path.end());
    auto owner = argument;
    std::vector<std::size_t> indices;
    for (const auto &name : path) {
      if (!checked.types->isProduct(owner) || checked.types->isSum(owner)) {
        error("type", call.span,
              "offset_of path does not select product fields");
        return inference.fresh();
      }
      const auto &fields = checked.types->product(owner).fields;
      auto field = std::find_if(
          fields.begin(), fields.end(),
          [&](const TypeField &entry) { return entry.name == name; });
      if (field == fields.end()) {
        error("name", call.span, "unknown offset_of field '" + name + "'");
        return inference.fresh();
      }
      auto index = static_cast<std::size_t>(field - fields.begin());
      visibleField(owner, index, call.span);
      indices.push_back(index);
      if (checked.types->pointerMetadata(field->type) ==
          PointerMetadata::Witness) {
        error("feature", call.span, "offset_of field alignment is dynamic");
        return inference.fresh();
      }
      owner = field->type;
    }
    facts(call).machineOperation = operation;
    facts(call).machineType = argument;
    facts(call).machineBorrowModes = {ParameterMode::Value};
    facts(call).argumentOrder = std::move(indices);
    return inference.fresh(Type::Usize);
  }
  if (operation == "numeric.to_int_unchecked") {
    if (argument == Type::Unknown && expectedTypes.contains(&call))
      argument = expectedTypes.at(&call);
    if (checked.types->isParameter(argument)) {
      error("feature", call.span,
            "unchecked float conversion requires a concrete integer target");
      return inference.fresh(argument);
    }
  }
  if (storageKind != AggregateKind::Product && argument == Type::Unknown &&
      expectedTypes.contains(&call) &&
      checked.types->isProduct(expectedTypes.at(&call)) &&
      checked.types->product(expectedTypes.at(&call)).kind == storageKind)
    argument = expectedTypes.at(&call);
  std::vector<Type> operands;
  std::vector<ParameterMode> borrowed;
  if (receiver >= 0) {
    auto mode = ParameterMode::Value;
    if (operation == "numeric.make_ascii_lowercase" ||
        operation == "numeric.make_ascii_uppercase") {
      mode = ParameterMode::Mut;
      requireMutablePlace(*callee.children[0]);
    }
    if (operation.starts_with("va.")) {
      mode = callee.text == "end"    ? ParameterMode::Take
             : callee.text == "copy" ? ParameterMode::Read
                                     : ParameterMode::Mut;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(*callee.children[0]);
    }
    if (operation.starts_with("cell.")) {
      mode = callee.text == "into_inner" ? ParameterMode::Take
             : callee.text == "get_mut"  ? ParameterMode::Mut
                                         : ParameterMode::Read;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(*callee.children[0]);
    }
    if (operation.starts_with("atomic.")) {
      mode = callee.text == "into_inner" ? ParameterMode::Take
             : callee.text == "get_mut"  ? ParameterMode::Mut
                                         : ParameterMode::Read;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(*callee.children[0]);
    }
    if (operation.starts_with("pin.")) {
      mode =
          callee.text == "into_inner" || callee.text == "into_inner_unchecked"
              ? ParameterMode::Take
          : callee.text == "as_mut" || callee.text == "get_mut" ||
                  callee.text == "get_unchecked_mut" ||
                  (operation.starts_with("pin.project.") &&
                   checked.types
                           ->view(checked.types->product(self).components[0])
                           .mode == ParameterMode::Mut)
              ? ParameterMode::Mut
              : ParameterMode::Read;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(*callee.children[0]);
    }
    if (mode == ParameterMode::Take && checked.types->isCopy(self))
      mode = ParameterMode::Value;
    if (storageKind != AggregateKind::Product) {
      mode = callee.text == "assume_init" || callee.text == "into_inner"
                 ? ParameterMode::Take
             : callee.text == "get_mut" || callee.text == "assume_init_mut" ||
                     callee.text == "as_mut_ptr" || callee.text == "write" ||
                     callee.text == "drop" ||
                     callee.text == "assume_init_drop" || callee.text == "take"
                 ? ParameterMode::Mut
                 : ParameterMode::Read;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(*callee.children[0]);
      if (mode == ParameterMode::Take && dereferences)
        error("ownership", call.span,
              "cannot consume storage through a viewed receiver");
    }
    if (mode == ParameterMode::Take && checked.types->isCopy(self))
      mode = ParameterMode::Value;
    if (mode == ParameterMode::Take && dereferences)
      error("ownership", call.span,
            "cannot consume a primitive receiver through a viewed handle");
    operands.push_back(mode == ParameterMode::Read || mode == ParameterMode::Mut
                           ? checked.types->viewType(self, mode)
                           : self);
    borrowed.push_back(mode);
  }
  auto operandErrors = diagnostics.count();
  for (std::size_t i = 1; i < call.children.size(); ++i) {
    auto &value = *call.children[i];
    if (operation == "intrinsics.panic_fmt" && i == 1) {
      auto *recipe = &value;
      while ((recipe->kind == Kind::Group || recipe->kind == Kind::Block) &&
             recipe->children.size() == 1 &&
             (recipe->kind != Kind::Block || !recipe->children[0]->semicolon))
        recipe = recipe->children[0].get();
      permittedRecipes.insert(recipe);
    }
    if (!value.name.empty())
      error("type", value.span,
            "primitive operations use positional arguments");
    Type expected = Type::Unknown;
    auto method = std::string_view(operation);
    if (operation.starts_with("atomic.")) {
      auto atomicMethod = method.substr(7);
      bool raw = atomicMethod.starts_with("raw_");
      if (raw)
        atomicMethod.remove_prefix(4);
      Type payload =
          receiver >= 0 ? checked.types->product(self).components[0]
          : operation == "atomic.new"
              ? checked.types->product(argument).components[0]
          : !operands.empty() && checked.types->isPointer(operands[0])
              ? checked.types->pointer(operands[0]).payload
              : Type::Unknown;
      auto position = operands.size();
      bool order = atomicMethod == "fence" ||
                   atomicMethod == "compiler_fence" ||
                   ((atomicMethod == "load" || atomicMethod == "fetch_not") &&
                    position == 1) ||
                   ((atomicMethod == "compare_exchange" ||
                     atomicMethod == "compare_exchange_weak")
                        ? position >= 3
                        : position == 2);
      if (order)
        expected = checked.types->structural(AggregateKind::Ordering, {});
      else if (operation == "atomic.new")
        expected = payload;
      else if (position == 1 &&
               (atomicMethod.starts_with("fetch_ptr_") ||
                atomicMethod.starts_with("fetch_byte_") ||
                (checked.types->isPointer(payload) &&
                 (atomicMethod == "fetch_and" || atomicMethod == "fetch_or" ||
                  atomicMethod == "fetch_xor"))))
        expected = Type::Usize;
      else if (position >= 1)
        expected = payload;
    }
    if (receiver >= 0 && isNumeric(self)) {
      auto numericMethod = method.substr(8);
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
      expected = numericMethod == "powi" ? Type::I32
                 : (numericMethod == "carrying_add" ||
                    numericMethod == "borrowing_sub") &&
                         i == 2
                     ? Type::Bool
                 : numericMethod.ends_with("add_signed") ||
                         numericMethod.ends_with("sub_signed")
                     ? signedType()
                 : numericMethod.ends_with("add_unsigned") ||
                         numericMethod.ends_with("sub_unsigned")
                     ? unsignedType()
                 : numericMethod.ends_with("_shl") ||
                         numericMethod.ends_with("_shr") ||
                         numericMethod == "unbounded_shl" ||
                         numericMethod == "unbounded_shr" ||
                         numericMethod == "unchecked_shl" ||
                         numericMethod == "unchecked_shr" ||
                         numericMethod.ends_with("_pow") ||
                         numericMethod == "pow" ||
                         method == "numeric.rotate_left" ||
                         method == "numeric.rotate_right"
                     ? Type::U32
                     : self;
    }
    if (receiver < 0 && operation == "numeric.to_int_unchecked")
      expected = self;
    else if (receiver < 0 && operation.starts_with("numeric.") &&
             operation != "numeric.from_bits" && isNumeric(argument))
      expected =
          i > 1 &&
                  (operation.ends_with("_shl") || operation.ends_with("_shr") ||
                   operation.ends_with("rotate_left") ||
                   operation.ends_with("rotate_right") ||
                   operation.ends_with("_pow") || operation == "numeric.pow")
              ? Type::U32
              : argument;
    if (receiver >= 0 && checked.types->isPointer(self)) {
      auto pointer = checked.types->pointer(self);
      if (method.starts_with("ptr.write"))
        expected = pointer.payload;
      else if (method.ends_with("offset"))
        expected = Type::Isize;
      else if (method.ends_with("add") || method.ends_with("sub") ||
               method == "ptr.with_addr")
        expected = Type::Usize;
    }
    if (operation == "ptr.without_provenance" ||
        operation == "ptr.with_exposed_provenance")
      expected = Type::Usize;
    if (operation == "numeric.from_bits")
      expected = argument == Type::F32 ? Type::U32 : Type::U64;
    if (receiver < 0 && operation.starts_with("numeric.from_") &&
        operation.ends_with("_bytes") && isNumeric(argument)) {
      auto width =
          isInteger(argument)
              ? integerWidth(argument, checked.targetDescription.pointerBits)
          : argument == Type::F32 ? 32u
                                  : 64u;
      expected = checked.types->arrayType(
          Type::U8, checked.types->constant(
                        Type::I32, static_cast<std::int64_t>(width / 8)));
    }
    if (operation == "ptr.copy" || operation == "ptr.copy_nonoverlapping" ||
        operation == "ptr.swap_nonoverlapping")
      expected = operands.size() == 2 ? Type::Usize : Type::Unknown;
    if (operation == "ptr.write_bytes")
      expected = operands.size() == 1   ? Type::U8
                 : operands.size() == 2 ? Type::Usize
                                        : Type::Unknown;
    if ((operation == "ptr.slice_from_raw_parts" ||
         operation == "ptr.slice_from_raw_parts_mut") &&
        i == 2)
      expected = Type::Usize;
    if (operation == "ptr.replace" && !operands.empty() &&
        checked.types->isPointer(operands[0]))
      expected = checked.types->pointer(operands[0]).payload;
    if (operation == "mem.replace" && !operands.empty() &&
        checked.types->isView(operands[0]))
      expected = checked.types->view(operands[0]).payload;
    if (operation == "storage.new" && argument != Type::Unknown)
      expected = checked.types->product(argument).components[0];
    if (operation == "cell.new" && argument != Type::Unknown)
      expected = checked.types->product(argument).components[0];
    if (operation == "cell.replace" || operation == "cell.set")
      expected = checked.types->product(self).components[0];
    if (operation == "storage.write")
      expected = checked.types->product(self).components[0];
    if (receiver < 0 && operation.starts_with("ptr.write") &&
        operation != "ptr.write_bytes" && !operands.empty() &&
        checked.types->isPointer(operands[0]))
      expected = checked.types->pointer(operands[0]).payload;
    contextualize(value, expected);
    auto variable = node(value, reachable);
    fields(false);
    if (expected != Type::Unknown)
      coerce(value, variable, inference.fresh(expected), value.span);
    auto type = inference.value(variable);
    auto mode = ParameterMode::Value;
    if (operation == "storage.new" || operation == "storage.write" ||
        operation == "pin.inline" || operation == "cell.new" ||
        operation == "cell.replace" || operation == "cell.set")
      mode = ParameterMode::Take;
    if (operation.starts_with("ptr.write") && operands.size() == 1)
      mode = ParameterMode::Take;
    if (operation == "mem.transmute" || operation == "mem.forget" ||
        operation == "mem.drop" || operation == "hint.black_box" ||
        (operation == "hint.select_unpredictable" && i >= 2) ||
        operation == "coroutine.start" ||
        (operation == "ptr.replace" && operands.size() == 1) ||
        (operation == "mem.replace" && operands.size() == 1))
      mode = ParameterMode::Take;
    if (mode == ParameterMode::Take && checked.types->isCopy(type))
      mode = ParameterMode::Value;
    if (i == 1 && (operation == "ptr.from_ref" || operation == "ptr.from_mut" ||
                   operation == "storage.from_mut")) {
      mode = operation != "ptr.from_ref" ? ParameterMode::Mut
                                         : ParameterMode::Read;
      if (checked.types->isView(type))
        type = checked.types->view(type).payload;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(value);
      type = checked.types->viewType(type, mode);
    }
    if ((operation == "mem.replace" && i == 1) ||
        (operation == "va.next_arg" && i == 1) ||
        (operation == "va.copy" && i == 1) ||
        (operation == "coroutine.resume" && i == 1) ||
        (operation == "mem.swap" && i <= 2) ||
        (operation == "intrinsics.panic_fmt" && i == 1) ||
        (operation == "intrinsics.variant_ordinal" && i == 1) ||
        (operation == "mem.transmute_copy" && i == 1) ||
        (operation == "mem.size_of_val" && i == 1) ||
        (operation == "mem.align_of_val" && i == 1)) {
      mode = operation.ends_with("_of_val") || operation == "va.copy" ||
                     operation == "intrinsics.panic_fmt" ||
                     operation == "intrinsics.variant_ordinal" ||
                     operation == "mem.transmute_copy"
                 ? ParameterMode::Read
                 : ParameterMode::Mut;
      if (checked.types->isView(type))
        type = checked.types->view(type).payload;
      if (mode == ParameterMode::Mut)
        requireMutablePlace(value);
      type = checked.types->viewType(type, mode);
    }
    if (operation == "cell.swap") {
      mode = ParameterMode::Read;
      if (checked.types->isView(type))
        type = checked.types->view(type).payload;
      type = checked.types->viewType(type, mode);
    }
    operands.push_back(type);
    borrowed.push_back(mode);
  }
  if (operation.starts_with("mem.") && operation != "mem.transmute" &&
      operation != "mem.transmute_copy" && operation != "mem.zeroed" &&
      operation != "mem.forget" && !operands.empty() &&
      checked.types->isView(operands[0]))
    argument = checked.types->view(operands[0]).payload;
  if ((operation == "ptr.slice_from_raw_parts" ||
       operation == "ptr.slice_from_raw_parts_mut") &&
      operands.size() == 2 && checked.types->isPointer(operands[0]))
    argument =
        checked.types->sliceType(checked.types->pointer(operands[0]).payload);
  if (operation == "intrinsics.variant_ordinal" && argument == Type::Unknown &&
      operands.size() == 1 && checked.types->isView(operands[0]))
    argument = checked.types->view(operands[0]).payload;
  if ((operation == "mem.size_of_val_raw" ||
       operation == "mem.align_of_val_raw") &&
      argument == Type::Unknown && operands.size() == 1 &&
      checked.types->isPointer(operands[0]))
    argument = checked.types->pointer(operands[0]).payload;
  if ((operation == "numeric.to_be_bytes" ||
       operation == "numeric.to_le_bytes" ||
       operation == "numeric.to_ne_bytes") &&
      operands.size() == 1 && isNumeric(operands[0])) {
    auto width =
        isInteger(operands[0])
            ? integerWidth(operands[0], checked.targetDescription.pointerBits)
        : operands[0] == Type::F32 ? 32u
                                   : 64u;
    argument = checked.types->arrayType(
        Type::U8, checked.types->constant(
                      Type::I32, static_cast<std::int64_t>(width / 8)));
  }
  if (operation == "numeric.sin_cos" && operands.size() == 1 &&
      isFloating(operands[0]))
    argument = checked.types->structural(AggregateKind::Tuple,
                                         {operands[0], operands[0]});
  if (operation == "coroutine.resume" && !operands.empty() &&
      checked.types->isView(operands[0]))
    argument = checked.types->view(operands[0]).payload;
  if (operation == "hint.black_box" && argument == Type::Unknown &&
      operands.size() == 1)
    argument = operands[0];
  if (operation == "hint.select_unpredictable" && argument == Type::Unknown &&
      operands.size() == 3 && operands[1] == operands[2])
    argument = operands[1];
  if (operation == "storage.new" && argument == Type::Unknown &&
      operands.size() == 1)
    argument = checked.types->structural(storageKind, {operands[0]});
  if (operation == "storage.from_mut" && argument == Type::Unknown &&
      operands.size() == 1 && checked.types->isView(operands[0]))
    argument = checked.types->structural(
        storageKind, {checked.types->view(operands[0]).payload});
  if (operation == "storage.raw_get" && argument == Type::Unknown &&
      operands.size() == 1 && checked.types->isPointer(operands[0]))
    argument = checked.types->pointer(operands[0]).payload;
  if (operation == "cell.new" && argument == Type::Unknown &&
      operands.size() == 1)
    argument = checked.types->structural(storageKind, {operands[0]});
  std::vector<Type> unpinProofs;
  Type unpinSubject = Type::Unknown;
  if (operation == "pin.new" && operands.size() == 1 &&
      checked.types->isView(operands[0]))
    unpinSubject = checked.types->view(operands[0]).payload;
  if ((operation == "pin.get_mut" || operation == "pin.into_inner") &&
      checked.types->isProduct(argument) &&
      checked.types->product(argument).kind == AggregateKind::Pin)
    unpinSubject =
        checked.types->view(checked.types->product(argument).components[0])
            .payload;
  if (operation == "intrinsics.fn_addr" || operation == "ptr.fn_addr_eq")
    for (auto operand : operands) {
      if (!checked.types->isParameter(operand))
        continue;
      auto assumptions = interfaceAssumptions();
      interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                diagnostics, std::move(assumptions),
                                regionEnvironment());
      bool bounded = false;
      for (std::size_t declaration = 0;
           declaration < checked.interfaceData->definitions.size();
           ++declaration) {
        const auto &definition =
            checked.interfaceData->definitions[declaration];
        if (definition.name != "core::clone::FunctionPointer" &&
            definition.name != "core::ops::FnPtr")
          continue;
        ErasedType marker;
        marker.name = definition.name;
        marker.declaration = static_cast<std::uint32_t>(declaration);
        if (solver.prove(
                {operand, checked.types->erasedType(std::move(marker))},
                call.span, false)) {
          bounded = true;
          break;
        }
      }
      if (!bounded) {
        error("type", call.span,
              "function address requires a function-pointer type or bound");
        return inference.fresh();
      }
    }
  if (unpinSubject != Type::Unknown && !checked.types->isUnpin(unpinSubject)) {
    std::set<Type> visited;
    auto conditional = [&](auto &&visit, Type type) -> bool {
      if (!visited.insert(type).second || !checked.types->isProduct(type) ||
          checked.types->isOpaque(type))
        return false;
      const auto &product = checked.types->product(type);
      if (product.layout.conditionalUnpin)
        return true;
      if (product.kind == AggregateKind::Array && !product.components.empty())
        return visit(visit, product.components[0]);
      for (const auto &field : product.fields)
        if (visit(visit, field.type))
          return true;
      return false;
    };
    // Region decoration is a later checking phase. Keep a request, never a
    // global type fact; that phase and IR admission must discharge it.
    if (unpinObligation(unpinSubject, call.span) ||
        conditional(conditional, unpinSubject))
      unpinProofs.push_back(unpinSubject);
  }
  auto signature = machineSignature(*checked.types, operation, operands,
                                    argument, unpinProofs);
  if (!signature) {
    if (diagnostics.count() == operandErrors)
      error("type", call.span, "invalid primitive operation or operand types");
    return inference.fresh();
  }
  if (signature->unsafeCall)
    requireUnsafe(call.span);
  if (operation == "va.next_arg" && checked.types->isParameter(argument)) {
    TypeSyntax safe;
    safe.name = "core::ffi::VaArgSafe";
    if (!interfaceObligation(argument, safe, call.span))
      return inference.fresh();
  }
  if (operation == "va.arg")
    if (auto vector = targetVector(checked.types->name(argument))) {
      if (vector->arch != checked.targetDescription.arch)
        error("feature", call.span, "variadic vector target mismatch");
      requireFeatures({vector->feature}, call.span);
    }
  using Shape = MachineSignature::Shape;
  auto result = signature->value;
  if (signature->shape == Shape::RefProjection ||
      signature->shape == Shape::RefMutProjection) {
    auto owner = checked.types->structural(AggregateKind::RefCell, {result});
    result = checked.types->structural(
        signature->shape == Shape::RefProjection ? AggregateKind::Ref
                                                 : AggregateKind::RefMut,
        {checked.types->viewType(owner, ParameterMode::Read)});
  } else if (signature->shape == Shape::UnguardedRef) {
    result = checked.types->structural(
        AggregateKind::Outcome,
        {checked.types->viewType(result, ParameterMode::Read),
         checked.types->structural(AggregateKind::BorrowError, {})});
  } else if (signature->shape == Shape::Ref ||
             signature->shape == Shape::RefMut ||
             signature->shape == Shape::TryRef ||
             signature->shape == Shape::TryRefMut) {
    bool exclusive = signature->shape == Shape::RefMut ||
                     signature->shape == Shape::TryRefMut;
    result = checked.types->structural(
        exclusive ? AggregateKind::RefMut : AggregateKind::Ref,
        {checked.types->viewType(result, ParameterMode::Read)});
    if (signature->shape == Shape::TryRef ||
        signature->shape == Shape::TryRefMut)
      result = checked.types->structural(
          AggregateKind::Outcome,
          {result,
           checked.types->structural(exclusive ? AggregateKind::BorrowMutError
                                               : AggregateKind::BorrowError,
                                     {})});
  } else if (signature->shape == Shape::Optional)
    result = checked.types->structural(AggregateKind::Optional, {result});
  else if (signature->shape == Shape::Overflow)
    result =
        checked.types->structural(AggregateKind::Tuple, {result, Type::Bool});
  else if (signature->shape == Shape::Pair)
    result = checked.types->structural(AggregateKind::Tuple, {result, result});
  else if (signature->shape == Shape::Outcome)
    result =
        checked.types->structural(AggregateKind::Outcome, {result, result});
  else if (signature->shape == Shape::PointerRead ||
           signature->shape == Shape::PointerMut)
    result = checked.types->pointerType(
        result, signature->shape == Shape::PointerMut ? ParameterMode::Mut
                                                      : ParameterMode::Read);
  else if (signature->shape == Shape::ViewRead ||
           signature->shape == Shape::ViewMut)
    result = checked.types->viewType(result, signature->shape == Shape::ViewMut
                                                 ? ParameterMode::Mut
                                                 : ParameterMode::Read);
  else if (signature->shape == Shape::ViewReadStatic)
    result =
        checked.types->viewType(result, ParameterMode::Read, RegionId::Static);
  else if (signature->shape == Shape::PinRead ||
           signature->shape == Shape::PinMut)
    result = checked.types->structural(
        AggregateKind::Pin,
        {checked.types->viewType(result, signature->shape == Shape::PinMut
                                             ? ParameterMode::Mut
                                             : ParameterMode::Read)});
  facts(call).machineOperation = std::move(operation);
  facts(call).unpinRequirements = std::move(unpinProofs);
  facts(call).dereferences = dereferences;
  facts(call).machineType = argument;
  facts(call).machineBorrowModes = std::move(borrowed);
  facts(call).callParameterTypes = std::move(operands);
  facts(call).method = receiver >= 0;
  return inference.fresh(result);
}
} // namespace mettle
