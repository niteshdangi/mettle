#include "semantics/checker.h"
#include <algorithm>
#include <set>

namespace mettle {
int Checker::join(Node &left, int a, Node &right, int b, Span span) {
  auto leftType = inference.value(a), rightType = inference.value(b);
  if (leftType != rightType && checked.types->isProduct(leftType) &&
      checked.types->isProduct(rightType)) {
    leftType = normalizeGenericType(leftType, {}, span);
    rightType = normalizeGenericType(rightType, {}, span);
    inference.set(a, leftType);
    inference.set(b, rightType);
  }
  if (leftType != rightType && checked.types->isView(leftType) &&
      checked.types->isView(rightType)) {
    auto mode =
        checked.types->view(leftType).mode == ParameterMode::Read ||
                checked.types->view(rightType).mode == ParameterMode::Read
            ? ParameterMode::Read
            : ParameterMode::Mut;
    std::set<Type> candidates;
    for (auto payload : {checked.types->view(leftType).payload,
                         checked.types->view(rightType).payload})
      if (receiverConversion(leftType, payload, mode, span, false) &&
          receiverConversion(rightType, payload, mode, span, false))
        candidates.insert(checked.types->viewType(payload, mode));
    if (candidates.size() == 1) {
      auto expected = inference.fresh(*candidates.begin());
      coerce(left, a, expected, span);
      coerce(right, b, expected, span);
      return expected;
    }
    if (candidates.size() > 1)
      error("type", span,
            "ambiguous dereference join requires a type annotation");
  }
  if (checked.types->isCallable(leftType) &&
      checked.types->isCallable(rightType)) {
    auto signature = checked.types->callable(leftType);
    auto pointer = checked.types->callableType(std::move(signature));
    if (compatibleCallable(leftType, pointer) &&
        compatibleCallable(rightType, pointer)) {
      auto expected = inference.fresh(pointer);
      coerce(left, a, expected, span);
      coerce(right, b, expected, span);
      return expected;
    }
  }
  auto optional = [&](int variable) {
    auto type = inference.value(variable);
    return checked.types->isProduct(type) &&
           checked.types->product(type).kind == AggregateKind::Optional;
  };
  if (optional(a) && !optional(b) && inference.value(b) != Type::Unknown &&
      inference.value(b) != Type::Never) {
    coerce(right, b, a, span);
    return a;
  }
  if (optional(b) && !optional(a) && inference.value(a) != Type::Unknown &&
      inference.value(a) != Type::Never) {
    coerce(left, a, b, span);
    return b;
  }
  return inference.joined(a, b, span);
}
void Checker::coerce(Node &expression, int actual, int expected, Span span) {
  auto source = inference.value(actual);
  auto target = inference.value(expected);
  if (source != target && checked.types->isProduct(source) &&
      checked.types->isProduct(target)) {
    source = normalizeGenericType(source, {}, span);
    target = normalizeGenericType(target, {}, span);
    inference.set(actual, source);
    inference.set(expected, target);
  }
  if (source != target && checked.types->isView(source) &&
      checked.types->isView(target)) {
    auto &conversion = facts(expression);
    conversion.viewConversion.reset();
    conversion.conversionView = Type::Unknown;
    conversion.unsizedSource = Type::Unknown;
    conversion.unsizedCount = Type::Unknown;
    conversion.erasedSource = Type::Unknown;
    conversion.reborrowSource = Type::Unknown;
    conversion.rebuiltType = Type::Unknown;
    auto apply = [&](Node &child) {
      coerce(child, nodeVariables.at(&child), expected, child.span);
    };
    bool distributed = false;
    if (expression.kind == Kind::Group) {
      apply(*expression.children[0]);
      distributed = true;
    } else if (expression.kind == Kind::Block && !expression.children.empty()) {
      apply(*expression.children.back());
      distributed = true;
    } else if (expression.kind == Kind::If && expression.children.size() == 3) {
      apply(*expression.children[1]);
      apply(*expression.children[2]);
      distributed = true;
    } else if (expression.kind == Kind::Match) {
      for (std::size_t i = 1; i < expression.children.size(); ++i)
        apply(*expression.children[i]->children.back());
      distributed = true;
    }
    if (distributed) {
      facts(expression).rebuiltType = target;
      return;
    }
  }
  if (source != target && checked.types->isView(source) &&
      checked.types->isView(target) &&
      checked.types->view(source).payload ==
          checked.types->view(target).payload &&
      checked.types->view(source).mode == ParameterMode::Mut &&
      checked.types->view(target).mode == ParameterMode::Read) {
    facts(expression).reborrowSource = source;
    facts(expression).rebuiltType = target;
    return;
  }
  if (source != target && ownerUnsizeCoercion(expression, source, target, span))
    return;
  if (source != target && unsizeCoercion(expression, source, target, span))
    return;
  if (source != target && checked.types->isView(source) &&
      checked.types->isView(target)) {
    const auto wanted = checked.types->view(target);
    bool directErase = false;
    if (checked.types->isErased(wanted.payload) &&
        !checked.types->isErased(checked.types->view(source).payload)) {
      interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                diagnostics, interfaceAssumptions(),
                                regionEnvironment());
      directErase = solver.prove(
          {checked.types->view(source).payload, wanted.payload}, span, false);
    }
    if (!directErase) {
      if (auto plan =
              receiverConversion(source, wanted.payload, wanted.mode, span)) {
        facts(expression).viewConversion = std::move(*plan);
        facts(expression).conversionView = target;
        if (wanted.mode == ParameterMode::Mut)
          requireMutablePlace(expression);
        return;
      }
    }
  }
  if (source != Type::Unknown && source != Type::Never && source != target &&
      checked.types->isOpaque(target)) {
    auto descriptor = checked.types->product(target);
    auto hidden = descriptor.fields[0].type;
    if (hidden != Type::Unknown && hidden != source) {
      error("type", span, "opaque return paths select different hidden types");
      return;
    }
    std::vector<TypeBinding> reveal{{target, source}};
    for (auto bound : descriptor.opaqueBounds)
      interfaceObligation(source, checked.types->substitute(bound, reveal),
                          span);
    if (descriptor.copyRequested && !checked.types->isCopy(source))
      error("type", span,
            "opaque hidden type does not satisfy its Copy contract");
    if (descriptor.layout.unpin == 1 && !unpinObligation(source, span))
      error("type", span,
            "opaque hidden type does not satisfy its Unpin contract");
    checked.types->defineProduct(target, {{"<hidden>", source}});
    facts(expression).opaqueSource = source;
    facts(expression).rebuiltType = target;
    return;
  }
  if (source != target && eraseCoercion(expression, source, target, span))
    return;
  if (source != target && compatibleCallable(source, target)) {
    facts(expression).callableCoercion = target;
    facts(expression).callableSource = source;
    facts(expression).rebuiltType = target;
    return;
  }
  if (source != Type::Unknown && target != Type::Unknown && source != target &&
      checked.types->isProduct(source) && checked.types->isProduct(target) &&
      checked.types->product(source).kind ==
          checked.types->product(target).kind &&
      (expression.kind == Kind::Tuple || expression.kind == Kind::Array)) {
    const auto &wanted = checked.types->product(target);
    if (checked.types->product(source).fields.size() == wanted.fields.size() &&
        (wanted.kind != AggregateKind::Array ||
         checked.types->arrayLength(source) ==
             checked.types->arrayLength(target))) {
      for (std::size_t i = 0; i < expression.children.size(); ++i) {
        if (expression.kind == Kind::Array && expression.flag && i == 1)
          break;
        auto &child = *expression.children[i];
        auto index = expression.kind == Kind::Array && expression.flag ? 0 : i;
        auto element = expression.kind == Kind::Array
                           ? wanted.components[0]
                           : wanted.fields[index].type;
        coerce(child, nodeVariables.at(&child), inference.fresh(element),
               child.span);
      }
      facts(expression).rebuiltType = target;
      return;
    }
  }
  if (source != Type::Unknown && source != Type::Never &&
      target != Type::Unknown && source != target) {
    std::vector<Type> layers;
    auto nested = target;
    while (checked.types->isProduct(nested) &&
           checked.types->product(nested).kind == AggregateKind::Optional) {
      layers.push_back(nested);
      nested = checked.types->product(nested).components[0];
      if (compatibleCallable(source, nested)) {
        facts(expression).callableCoercion = nested;
        facts(expression).callableSource = source;
        facts(expression).rebuiltType = nested;
        std::reverse(layers.begin(), layers.end());
        facts(expression).injections = std::move(layers);
        return;
      }
      if (nested == source) {
        std::reverse(layers.begin(), layers.end());
        facts(expression).injections = std::move(layers);
        return;
      }
    }
  }
  inference.equal(actual, expected, span, true);
}
} // namespace mettle
