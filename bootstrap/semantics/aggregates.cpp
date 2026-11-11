#include "semantics/checker.h"
#include "support/limits.h"

namespace mettle {
int Checker::aggregate(Node &n, bool reachable) {
  if (n.kind == Kind::Tuple) {
    std::vector<int> children;
    for (auto &child : n.children)
      children.push_back(node(*child, reachable));
    return inference.composite(AggregateKind::Tuple, std::move(children));
  }
  if (n.kind == Kind::Array) {
    int payload = inference.fresh();
    std::uint32_t count = n.children.size();
    if (n.flag) {
      node(*n.children[1], reachable);
      auto identity = constantType(*n.children[1]);
      if (identity != Type::Unknown &&
          !isInteger(checked.types->parameter(identity).valueType)) {
        error("type", n.span, "array length requires an integer constant");
        return inference.fresh();
      }
      auto scalar = checked.types->scalarConstantValue(identity);
      if (scalar && scalar->negative) {
        error(
            "type", n.span,
            "array repetition requires a bounded nonnegative integer constant");
        return inference.fresh();
      }
      std::optional<std::uint64_t> evaluated;
      if (scalar && !scalar->magnitude[1])
        evaluated = scalar->magnitude[0];
      if (identity != Type::Unknown && scalar && !evaluated) {
        error("limit", n.span, "array length limit exceeded");
        return inference.fresh();
      }
      if (identity != Type::Unknown && !evaluated) {
        inference.equal(payload, node(*n.children[0], reachable), n.span);
        facts(n).constantCount = identity;
        return inference.composite(AggregateKind::Array, {payload}, 0,
                                   identity);
      }
      auto length = evaluated;
      if (!length)
        error(
            "type", n.span,
            "array repetition requires a bounded nonnegative integer constant");
      if (length && *length > TypeStore::expandedArrayLimit) {
        // Large repetitions stay one symbolic repeat over a compact array.
        inference.equal(payload, node(*n.children[0], reachable), n.span);
        facts(n).constantCount = identity;
        return inference.composite(AggregateKind::Array, {payload}, 0,
                                   checked.types->canonicalCount(identity));
      }
      count = length ? static_cast<std::uint32_t>(*length) : 0;
      inference.equal(payload, node(*n.children[0], reachable), n.span);
    } else
      for (auto &child : n.children)
        inference.equal(payload, node(*child, reachable), child->span);
    facts(n).number = static_cast<std::int32_t>(count);
    return inference.composite(AggregateKind::Array, {payload}, count);
  }
  if (n.kind == Kind::Range) {
    if (!n.name.empty()) {
      std::string target;
      if (n.name == "from")
        target = "core::iter::range_from";
      else if (n.name == "to")
        target = n.text == "..=" ? "core::iter::range_to_inclusive"
                                 : "core::iter::range_to";
      else if (n.name == "full")
        target = "core::iter::range_full";
      if (target.empty()) {
        error("feature", n.span,
              "open-ended range values require the core.iter range types");
        return inference.fresh();
      }
      auto found = names.find(callableName(target, current->owner, n.span));
      if (found == names.end()) {
        error("feature", n.span,
              "open-ended range values require the core.iter range types");
        return inference.fresh();
      }
      auto callee = std::make_unique<Node>();
      callee->kind = Kind::Name;
      callee->span = n.span;
      callee->text = std::move(target);
      std::vector<NodeOwner> children;
      children.push_back(std::move(callee));
      for (auto &child : n.children)
        children.push_back(std::move(child));
      n.children = std::move(children);
      n.kind = Kind::Call;
      n.text.clear();
      n.name.clear();
      return call(n, reachable);
    }
    if (!loopRanges.contains(&n)) {
      // Outside a `for` source the range is the library `core.iter` value so
      // that it is an Iterator; without `core` it stays structural.
      std::string target =
          n.text == "..=" ? "core::iter::range_inclusive" : "core::iter::range";
      if (auto found = names.find(callableName(target, current->owner, n.span));
          found != names.end()) {
        auto callee = std::make_unique<Node>();
        callee->kind = Kind::Name;
        callee->span = n.span;
        callee->text = std::move(target);
        std::vector<NodeOwner> children;
        children.push_back(std::move(callee));
        for (auto &child : n.children)
          children.push_back(std::move(child));
        n.children = std::move(children);
        n.kind = Kind::Call;
        n.text.clear();
        return call(n, reachable);
      }
    }
    auto lower = node(*n.children[0], reachable);
    auto upper = node(*n.children[1], reachable);
    inference.equal(lower, upper, n.span);
    if (inference.value(lower) != Type::Char)
      inference.equal(lower, inference.numeric(false), n.span);
    return inference.composite(AggregateKind::Range,
                               {lower, upper, inference.fresh(Type::Bool)});
  }
  if (n.kind == Kind::Index) {
    int base = node(*n.children[0], reachable);
    const bool sliced = n.children[1]->kind == Kind::Range;
    int key = -1;
    if (sliced)
      for (auto &bound : n.children[1]->children)
        inference.equal(node(*bound, reachable), inference.fresh(Type::Usize),
                        bound->span, true);
    else
      key = node(*n.children[1], reachable);
    fields(false);
    auto type = inference.value(base);
    while (checked.types->isView(type))
      type = checked.types->view(type).payload;
    if (type != Type::Unknown && !checked.types->isSlice(type) &&
        !(checked.types->isProduct(type) &&
          checked.types->product(type).kind == AggregateKind::Array)) {
      if (auto result = operatorCall(n, base, key)) {
        auto view = inference.value(*result);
        if (checked.types->isView(view)) {
          facts(n).indexView = view;
          facts(n).operatorCall = false;
          if (facts(n).exclusivePlace)
            requireMutablePlace(n);
          return inference.fresh(checked.types->view(view).payload);
        }
        return *result;
      }
      if (sliced) {
        error("type", n.span,
              "range indexing requires an array, slice or a type "
              "implementing core.ops.IndexRange");
        return inference.fresh();
      }
    }
    auto keyType = sliced ? Type::Usize : inference.value(key);
    if (keyType != Type::Usize)
      inference.equal(key, inference.fresh(Type::I32), n.children[1]->span,
                      true);
    int result = inference.fresh();
    fieldRequests.push_back({&n, base, result});
    return result;
  }
  if (n.kind == Kind::Coalesce) {
    int source = node(*n.children[0], reachable);
    auto children =
        inference.components(source, AggregateKind::Optional, n.span);
    int fallback = node(*n.children[1], reachable);
    if (children.empty())
      return fallback;
    return inference.joined(children[0], fallback, n.span);
  }
  loopResults[facts(n).control] = inference.fresh(Type::Unit);
  if (auto *iterable = n.children[0].get(); iterable) {
    while (iterable->kind == Kind::Group)
      iterable = iterable->children[0].get();
    if (iterable->kind == Kind::Range && iterable->name.empty())
      loopRanges.insert(iterable);
  }
  int source = node(*n.children[0], reachable);
  auto type = inference.value(source);
  if (type == Type::Unknown) {
    fields(false);
    type = inference.value(source);
  }
  if (type == Type::Never) {
    scopes.emplace_back();
    pattern(n.patterns[0], inference.fresh(), ParameterMode::Read);
    irrefutable.emplace_back(&n.patterns[0],
                             patternVariables.at(&n.patterns[0]));
    node(*n.children[1], false);
    scopes.pop_back();
    return inference.fresh(facts(n).flow.normal ? Type::Unit : Type::Never);
  }
  bool consumes =
      n.children[0]->kind == Kind::Unary && n.children[0]->text == "take";
  facts(n).iterationMode =
      checked.types->isView(type) &&
              checked.types->view(type).mode == ParameterMode::Mut
          ? ParameterMode::Mut
      : consumes && !checked.types->isView(type) ? ParameterMode::Take
                                                 : ParameterMode::Read;
  while (checked.types->isView(type))
    type = checked.types->view(type).payload;
  if (!checked.types->isSlice(type) &&
      (!checked.types->isProduct(type) ||
       (checked.types->product(type).kind != AggregateKind::Range &&
        checked.types->product(type).kind != AggregateKind::Array))) {
    if (type != Type::Unknown && desugarIteration(n, inference.value(source)))
      return node(*checked.iterations.at(&n).elaboration, reachable);
    error("type", n.span,
          "for requires a concrete range or array, or an iterator, "
          "collection or view implementing core.iter.Iterator, OwnedIterable, "
          "Iterable or MutableIterable for its mode");
    return inference.fresh(Type::Unit);
  }
  facts(n).readView = checked.types->viewType(
      type, facts(n).iterationMode == ParameterMode::Mut ? ParameterMode::Mut
                                                         : ParameterMode::Read);
  auto payload = checked.types->isSlice(type)
                     ? checked.types->slice(type).element
                 : checked.types->product(type).kind == AggregateKind::Range
                     ? checked.types->product(type).components[0]
                     : checked.types->product(type).components[0];
  if (facts(n).iterationMode != ParameterMode::Take)
    facts(n).elementView =
        checked.types->viewType(payload, facts(n).iterationMode);
  scopes.emplace_back();
  pattern(n.patterns[0], inference.fresh(payload), facts(n).iterationMode);
  irrefutable.emplace_back(&n.patterns[0], patternVariables.at(&n.patterns[0]));
  node(*n.children[1], reachable);
  scopes.pop_back();
  return inference.fresh(Type::Unit);
}
} // namespace mettle
