#include "semantics/checker.h"
#include "types/target.h"
#include <algorithm>

namespace mettle {
std::optional<Type> Checker::machineAnnotation(const TypeSyntax &syntax,
                                               Span span,
                                               std::string_view owner) {
  if (syntax.form != TypeForm::Named || syntax.nested || !syntax.view.empty())
    return std::nullopt;
  if (checked.symbols->lookup(checked.symbols->moduleOf(span), syntax.name,
                              resolution::Namespace::Type, span))
    return std::nullopt;
  if (auto descriptor = targetVector(syntax.name)) {
    if (descriptor->arch != checked.targetDescription.arch ||
        !checked.targetDescription.initialProfile())
      error("feature", span,
            "native vector type is unavailable on this target");
    if (!syntax.arguments.empty())
      error("type", span,
            "native vector aliases do not take generic arguments");
    return checked.types->vectorType(descriptor->name, descriptor->element,
                                     descriptor->lanes, descriptor->alignment);
  }
  for (auto [name, type] : {std::pair{"core::arch::x86_64::__mmask8", Type::U8},
                            {"core::arch::x86_64::__mmask16", Type::U16},
                            {"core::arch::x86_64::__mmask32", Type::U32},
                            {"core::arch::x86_64::__mmask64", Type::U64}})
    if (syntax.name == name) {
      if (checked.targetDescription.arch != TargetArch::X86_64 ||
          !checked.targetDescription.initialProfile())
        error("feature", span, "mask alias is unavailable on this target");
      if (!syntax.arguments.empty())
        error("type", span,
              "native mask aliases do not take generic arguments");
      return type;
    }
  if (syntax.name.starts_with("core::arch::")) {
    error("feature", span,
          "unsupported native type in the initial target inventory");
    return Type::Unknown;
  }
  if (syntax.name == "core::marker::PhantomPinned")
    return checked.types->structural(AggregateKind::PhantomPinned, {});
  if (syntax.name == "core::sync::atomic::Ordering")
    return checked.types->structural(AggregateKind::Ordering, {});
  if (syntax.name == "core::cell::BorrowError" ||
      syntax.name == "core::cell::BorrowMutError")
    return checked.types->structural(syntax.name == "core::cell::BorrowError"
                                         ? AggregateKind::BorrowError
                                         : AggregateKind::BorrowMutError,
                                     {});
  if (syntax.name.starts_with("core::sync::atomic::Atomic")) {
    auto suffix =
        syntax.name.substr(std::string("core::sync::atomic::Atomic").size());
    Type payload = Type::Unknown;
    for (auto [name, type] : {std::pair{"Bool", Type::Bool},
                              {"I8", Type::I8},
                              {"U8", Type::U8},
                              {"I16", Type::I16},
                              {"U16", Type::U16},
                              {"I32", Type::I32},
                              {"U32", Type::U32},
                              {"I64", Type::I64},
                              {"U64", Type::U64},
                              {"Isize", Type::Isize},
                              {"Usize", Type::Usize}})
      if (suffix == name)
        payload = type;
    if (suffix == "Ptr") {
      if (syntax.arguments.size() != 1 || !syntax.arguments[0].type) {
        error("type", span, "atomic pointer requires one pointee type");
        return Type::Unknown;
      }
      auto pointee = annotation(*syntax.arguments[0].type, span, owner);
      if (!checked.types->isSized(pointee)) {
        error("type", span, "atomic pointer requires a thin pointer payload");
        return Type::Unknown;
      }
      payload = checked.types->pointerType(pointee, ParameterMode::Mut);
    } else if (!syntax.arguments.empty())
      error("type", span,
            "scalar atomic aliases do not accept type parameters");
    if (payload == Type::Unknown) {
      error(
          "feature", span,
          "atomic width is not provided as a target-supported lock-free alias");
      return Type::Unknown;
    }
    return checked.types->structural(AggregateKind::Atomic, {payload});
  }
  auto family =
      syntax.name == "core::mem::MaybeUninit"    ? AggregateKind::Uninit
      : syntax.name == "core::mem::ManuallyDrop" ? AggregateKind::ManualDrop
      : syntax.name == "core::cell::UnsafeCell"  ? AggregateKind::UnsafeCell
      : syntax.name == "core::cell::Cell"        ? AggregateKind::Cell
      : syntax.name == "core::cell::RefCell"     ? AggregateKind::RefCell
      : syntax.name == "core::cell::Ref"         ? AggregateKind::Ref
      : syntax.name == "core::cell::RefMut"      ? AggregateKind::RefMut
                                                 : AggregateKind::Product;
  if (family == AggregateKind::Product)
    return std::nullopt;
  if (syntax.arguments.size() != 1 || !syntax.arguments[0].type) {
    error("type", span, "storage type requires one payload type");
    return Type::Unknown;
  }
  auto payload = annotation(*syntax.arguments[0].type, span, owner);
  if (family == AggregateKind::Ref || family == AggregateKind::RefMut)
    payload = checked.types->viewType(
        checked.types->structural(AggregateKind::RefCell, {payload}),
        ParameterMode::Read);
  if (family == AggregateKind::Uninit && !checked.types->isSized(payload))
    error("type", span, "uninitialized by-value storage requires Sized");
  return checked.types->structural(family, {payload});
}
std::optional<int> Checker::machineValue(const Node &node) {
  if (checked.symbols->lookup(checked.symbols->moduleOf(node.span), node.text,
                              resolution::Namespace::Value, node.span))
    return std::nullopt;
  if (node.text == "core::marker::PhantomPinned") {
    facts(node).machineOperation = "marker.phantom_pinned";
    return inference.fresh(
        checked.types->structural(AggregateKind::PhantomPinned, {}));
  }
  auto separator = node.text.rfind("::");
  if (separator == std::string::npos)
    return std::nullopt;
  auto owner = node.text.substr(0, separator),
       member = node.text.substr(separator + 2);
  if (owner == "core::sync::atomic::Ordering") {
    const std::vector<std::string> names{"Relaxed", "Release", "Acquire",
                                         "AcqRel", "SeqCst"};
    auto found = std::find(names.begin(), names.end(), member);
    if (found != names.end()) {
      auto type = checked.types->structural(AggregateKind::Ordering, {});
      facts(node).variant = static_cast<int>(found - names.begin());
      return inference.fresh(type);
    }
  }
  auto type = builtinType(owner);
  if (!isInteger(type) || (member != "MIN" && member != "MAX"))
    return std::nullopt;
  NumericLiteral literal;
  auto width = integerWidth(type);
  auto bits =
      member == "MAX" ? width - (isSignedInteger(type) ? 1 : 0) : width - 1;
  if (member == "MIN") {
    if (isSignedInteger(type)) {
      literal.negative = true;
      literal.magnitude[bits / 64] = std::uint64_t{1} << (bits % 64);
    }
  } else {
    literal.magnitude[0] =
        bits >= 64 ? ~std::uint64_t{0} : (std::uint64_t{1} << bits) - 1;
    if (bits > 64)
      literal.magnitude[1] = bits == 128
                                 ? ~std::uint64_t{0}
                                 : (std::uint64_t{1} << (bits - 64)) - 1;
  }
  facts(node).numeric = literal;
  return inference.fresh(type);
}
} // namespace mettle
