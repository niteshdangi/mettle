#include "semantics/checker.h"

namespace mettle {
std::optional<int> Checker::variantCall(Node &n, std::string_view spelling,
                                        bool reachable) {
  auto canonical =
      checked.symbols->lookup(checked.symbols->moduleOf(n.span), spelling,
                              resolution::Namespace::Value, n.span);
  auto resolved = canonical ? std::string_view(*canonical) : spelling;
  auto delimiter = resolved.rfind("::");
  if (delimiter == std::string_view::npos)
    return std::nullopt;
  auto prefix = resolved.substr(0, delimiter);
  auto name = std::string(resolved.substr(delimiter + 2));
  auto owner = canonical
                   ? std::string(prefix)
                   : typeName(prefix, n.span, current ? current->owner : "");
  auto found = typeNames.find(owner);
  if (found == typeNames.end() || !checked.types->isSum(found->second))
    return std::nullopt;
  auto type = found->second;
  const auto &product = checked.types->product(type);
  int variant = -1;
  for (std::size_t i = 0; i < product.variants.size(); ++i)
    if (product.variants[i].name == name)
      variant = static_cast<int>(i);
  if (variant < 0) {
    error("name", n.span, "unknown variant '" + name + "'");
    return inference.fresh(type);
  }
  facts(n).variant = variant;
  auto count = n.kind == Kind::Call ? n.children.size() - 1 : 0;
  const auto &fields = product.variants[variant].fields;
  if (count != fields.size())
    error("type", n.span, "variant argument count does not match");
  std::vector<bool> used(fields.size());
  bool named = false;
  for (std::size_t i = 0; i < count; ++i) {
    auto &argument = *n.children[i + 1];
    auto target = i;
    if (!argument.name.empty()) {
      named = true;
      target = fields.size();
      for (std::size_t field = 0; field < fields.size(); ++field)
        if (product.fields[fields[field]].name == argument.name)
          target = field;
    } else if (named)
      error("type", argument.span,
            "positional arguments must precede named arguments");
    auto actual = node(argument, reachable);
    if (target >= fields.size()) {
      error("type", argument.span, "unknown or excess variant argument");
      continue;
    }
    if (used[target])
      error("type", argument.span, "duplicate variant argument");
    used[target] = true;
    facts(n).argumentOrder.push_back(target);
    coerce(argument, actual,
           inference.fresh(product.fields[fields[target]].type), argument.span);
  }
  return inference.fresh(type);
}

int Checker::sumExpression(Node &n, bool reachable) {
  if (n.kind == Kind::None) {
    facts(n).variant = 0;
    return inference.composite(AggregateKind::Optional, {inference.fresh()});
  }
  if (n.kind == Kind::Variant) {
    int payload = node(*n.children[0], reachable);
    facts(n).variant = n.text == "failure" ? 1 : (n.text == "present" ? 1 : 0);
    if (n.text == "present")
      return inference.composite(AggregateKind::Optional, {payload});
    auto unknown = inference.fresh();
    return inference.composite(AggregateKind::Outcome,
                               n.text == "success"
                                   ? std::vector<int>{payload, unknown}
                                   : std::vector<int>{unknown, payload});
  }
  if (n.kind == Kind::Throw) {
    auto errorType = facts(*current).error;
    int value = node(*n.children[0], reachable);
    if (errorType == Type::Unknown && !effectContext)
      error("effects", n.span, "throw requires an explicit throws contract");
    else if (errorType != Type::Unknown)
      inference.equal(value, inference.fresh(errorType), n.span, true);
    if (effectContext)
      facts(n).effect =
          errorType == Type::Unknown ? inference.value(value) : errorType;
    return inference.fresh(Type::Never);
  }
  auto enclosing = effectContext;
  ++effectContext;
  int operand = node(*n.children[0], reachable);
  --effectContext;
  auto effect = facts(*n.children[0]).effect;
  if (effect == Type::Unknown) {
    error("effects", n.span,
          "try/capture requires a typed throwing expression");
    return operand;
  }
  facts(n).effect = Type::Unknown;
  if (n.kind == Kind::Capture)
    return inference.composite(AggregateKind::Outcome,
                               {operand, inference.fresh(effect)});
  if (!enclosing && facts(*current).error != effect)
    error("effects", n.span,
          "propagated error must match the declared throws type");
  if (enclosing)
    facts(n).effect = effect;
  return operand;
}
} // namespace mettle
