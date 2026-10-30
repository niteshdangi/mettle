#include "semantics/checker.h"
#include "syntax/lexer.h"
#include <charconv>
#include <functional>
#include <map>
#include <set>

namespace mettle {
void Checker::pattern(Pattern &p, int variable, ParameterMode mode) {
  patternVariables[&p] = variable;
  auto type = inference.value(variable);
  if (p.kind == PatternKind::Wildcard)
    return;
  if (p.kind == PatternKind::Rest) {
    error("type", p.span, "rest pattern requires an array context");
    return;
  }
  if (p.kind == PatternKind::Binding && p.children.empty())
    if (auto storage = staticName(p.text, p.span);
        storage && module.statics[*storage].constant) {
      // A scalar `const` name in a pattern matches its value, like a literal.
      auto value = staticValue(*storage);
      if (!value)
        return;
      const auto valueType = value->type;
      if (valueType == Type::Bool) {
        p.text = value->scalar.magnitude[0] ? "true" : "false";
        p.literalKind = TokenKind::Word;
      } else if (isInteger(valueType)) {
        p.text = integerLiteralName(value->scalar);
        p.literalKind = TokenKind::Integer;
      } else {
        error("type", p.span,
              "only integer and bool constants can be used as patterns");
        return;
      }
      p.kind = PatternKind::Literal;
    }
  if (p.kind == PatternKind::Binding || p.kind == PatternKind::At) {
    auto prior = scopes.back().find(p.text);
    if (prior != scopes.back().end()) {
      error("name", p.span, "duplicate pattern binding '" + p.text + "'");
      return;
    }
    auto slot = local(p.text, variable, mode == ParameterMode::Mut, p.span);
    facts(p).slot = slot;
    if (slot >= 0 &&
        (mode == ParameterMode::Mut ||
         (mode == ParameterMode::Read && !checked.types->isCopy(type)))) {
      facts(*current).locals[slot].patternView = true;
      facts(*current).locals[slot].mode = mode;
    }
    if (p.kind == PatternKind::At) {
      if (mode == ParameterMode::Take && !checked.types->isCopy(type))
        error("ownership", p.span,
              "non-Copy at-pattern cannot move both whole value and payload");
      pattern(p.children[0], variable, mode);
    }
    return;
  }
  if (p.kind == PatternKind::Literal || p.kind == PatternKind::Range) {
    auto literalType = p.literalKind == TokenKind::Character   ? Type::Char
                       : p.literalKind == TokenKind::Byte      ? Type::U8
                       : p.text == "true" || p.text == "false" ? Type::Bool
                                                               : Type::Unknown;
    if (literalType == Type::Unknown) {
      Node syntax{};
      syntax.kind = Kind::Integer;
      syntax.span = p.span;
      auto negative = p.text.starts_with("-");
      syntax.text = negative ? p.text.substr(1) : p.text;
      auto suffix = literal(syntax, negative);
      facts(p).numeric = facts(syntax).numeric;
      checked.nodes.erase(&syntax);
      inference.equal(variable, inference.numeric(false, suffix), p.span);
    } else {
      inference.equal(variable, inference.fresh(literalType), p.span);
      std::int32_t number = 0;
      if (literalType == Type::Char || literalType == Type::U8) {
        auto decoded = characterLiteral(p.text, literalType == Type::U8,
                                        diagnostics, p.span);
        if (decoded)
          number = static_cast<std::int32_t>(*decoded);
      } else
        number = p.text == "true";
      facts(p).number = number;
      facts(p).numeric = integerLiteral(number);
    }
    if (p.kind == PatternKind::Range) {
      if (literalType == Type::Bool)
        error("type", p.span,
              "range pattern requires integer or scalar bounds");
      pattern(p.children[0], variable, mode);
      auto lower = facts(p).numeric, upper = facts(p.children[0]).numeric;
      if (lower && upper &&
          (compareIntegers(*lower, *upper) > 0 ||
           (!p.inclusive && compareIntegers(*lower, *upper) == 0)))
        error("type", p.span, "empty or reversed range pattern");
    }
    return;
  }
  if (p.kind == PatternKind::Or) {
    auto saved = scopes.back();
    std::map<std::string, Binding> bindings;
    for (std::size_t i = 0; i < p.children.size(); ++i) {
      scopes.back() = saved;
      pattern(p.children[i], variable, mode);
      std::map<std::string, Binding> currentBindings;
      for (const auto &[name, binding] : scopes.back())
        if (!saved.contains(name))
          currentBindings.emplace(name, binding);
      if (i == 0)
        bindings = currentBindings;
      else {
        if (currentBindings.size() != bindings.size())
          error("type", p.span,
                "or-pattern alternatives must bind identical names");
        for (const auto &[name, binding] : currentBindings) {
          auto found = bindings.find(name);
          if (found == bindings.end()) {
            error("type", p.span,
                  "or-pattern alternatives must bind identical names");
            continue;
          }
          inference.equal(binding.variable, found->second.variable, p.span);
          std::function<void(Pattern &)> remap = [&](Pattern &child) {
            if ((child.kind == PatternKind::Binding ||
                 child.kind == PatternKind::At ||
                 child.kind == PatternKind::Rest) &&
                child.text == name)
              facts(child).slot = found->second.slot;
            for (auto &nested : child.children)
              remap(nested);
          };
          remap(p.children[i]);
        }
      }
    }
    scopes.back() = saved;
    for (const auto &[name, binding] : bindings)
      scopes.back()[name] = binding;
    return;
  }
  if (p.kind == PatternKind::Tuple || p.kind == PatternKind::Array) {
    auto shape = p.kind == PatternKind::Tuple ? AggregateKind::Tuple
                                              : AggregateKind::Array;
    std::vector<int> payloads;
    if (type != Type::Unknown && checked.types->compactArray(type)) {
      error("feature", p.span,
            "array patterns over large arrays are not implemented");
      return;
    }
    if (type != Type::Unknown && checked.types->isProduct(type) &&
        checked.types->product(type).kind == shape) {
      for (const auto &field : checked.types->product(type).fields)
        payloads.push_back(inference.fresh(field.type));
    } else {
      error("type", p.span, "pattern requires a resolved aggregate type");
      return;
    }
    auto rest = p.children.size();
    for (std::size_t i = 0; i < p.children.size(); ++i)
      if (p.children[i].kind == PatternKind::Rest) {
        if (rest != p.children.size() || p.kind != PatternKind::Array)
          error("type", p.span, "array pattern has more than one rest");
        rest = i;
      }
    if ((rest == p.children.size() && payloads.size() != p.children.size()) ||
        (rest != p.children.size() &&
         payloads.size() + 1 < p.children.size())) {
      error("type", p.span, "pattern length does not match");
      return;
    }
    for (std::size_t i = 0; i < p.children.size(); ++i) {
      auto index = i <= rest ? i : payloads.size() - (p.children.size() - i);
      facts(p).fields.push_back(static_cast<std::uint32_t>(index));
      if (i == rest) {
        auto &child = p.children[i];
        auto count = payloads.size() - (p.children.size() - 1);
        auto element = checked.types->product(type).components[0];
        auto subarray = checked.types->structural(
            AggregateKind::Array, {element}, static_cast<std::uint32_t>(count));
        patternVariables[&child] = inference.fresh(subarray);
        facts(child).slice =
            Projection::slice(static_cast<std::uint32_t>(index),
                              static_cast<std::uint32_t>(count), subarray);
        for (std::size_t field = index; field < index + count; ++field)
          facts(child).fields.push_back(static_cast<std::uint32_t>(field));
        if (!child.text.empty()) {
          auto slot = local(child.text, patternVariables[&child],
                            mode == ParameterMode::Mut, child.span);
          facts(child).slot = slot;
          if (slot >= 0 && (mode == ParameterMode::Mut ||
                            (mode == ParameterMode::Read &&
                             !checked.types->isCopy(subarray)))) {
            facts(*current).locals[slot].patternView = true;
            facts(*current).locals[slot].mode = mode;
          }
        }
      } else
        pattern(p.children[i], payloads[index], mode);
    }
    return;
  }
  std::vector<int> payloads;
  auto diagnosticsBefore = diagnostics.count();
  if (p.text == "none" || p.text == "present") {
    auto components =
        inference.components(variable, AggregateKind::Optional, p.span);
    facts(p).variant = p.text == "none" ? 0 : 1;
    if (p.text == "present" && !components.empty()) {
      facts(p).fields = {1};
      payloads = {components[0]};
    }
  } else if (p.text == "success" || p.text == "failure") {
    auto components =
        inference.components(variable, AggregateKind::Outcome, p.span);
    facts(p).variant = p.text == "success" ? 0 : 1;
    if (components.size() == 2) {
      facts(p).fields = {p.text == "success" ? 1u : 2u};
      payloads = {components[facts(p).variant]};
    }
  } else {
    auto canonical =
        checked.symbols->lookup(checked.symbols->moduleOf(p.span), p.text,
                                resolution::Namespace::Value, p.span);
    auto spelling = canonical ? *canonical : p.text;
    auto delimiter = spelling.rfind("::");
    auto productName =
        canonical ? spelling : typeName(p.text, p.span, current->owner);
    auto owner =
        p.kind == PatternKind::Product && typeNames.contains(productName)
            ? productName
        : canonical
            ? spelling.substr(0, delimiter)
            : typeName(spelling.substr(0, delimiter), p.span, current->owner);
    auto found = typeNames.find(owner);
    if (found == typeNames.end() || !checked.types->isProduct(found->second)) {
      error("name", p.span, "unknown pattern constructor '" + p.text + "'");
      return;
    }
    if (type == Type::Unknown) {
      std::set<int> roots;
      for (auto poisoned : poisonedVariables)
        roots.insert(inference.representative(poisoned));
      // The scrutinee already failed to check; instantiating the pattern's
      // generic type with its own parameters would only add a second error.
      if (inference.depends(variable, roots)) {
        for (auto &child : p.children) {
          auto binding = inference.fresh();
          poisonedVariables.push_back(binding);
          pattern(child, binding, mode);
        }
        return;
      }
    }
    auto expected = type;
    type = found->second;
    if (checked.types->isProduct(expected) &&
        checked.types->product(expected).genericOrigin == type)
      type = expected;
    inference.equal(variable, inference.fresh(type), p.span);
    const auto &product = checked.types->product(type);
    if (checked.types->isSum(type)) {
      auto name = spelling.substr(delimiter + 2);
      for (std::size_t i = 0; i < product.variants.size(); ++i)
        if (product.variants[i].name == name)
          facts(p).variant = static_cast<int>(i);
      if (facts(p).variant < 0) {
        error("name", p.span, "unknown variant pattern '" + p.text + "'");
        return;
      }
      facts(p).fields = product.variants[facts(p).variant].fields;
    } else {
      if (p.kind != PatternKind::Product) {
        error("type", p.span, "product pattern requires named fields");
        return;
      }
      for (std::size_t i = 0; i < product.fields.size(); ++i)
        facts(p).fields.push_back(static_cast<std::uint32_t>(i));
    }
    for (auto field : facts(p).fields)
      payloads.push_back(inference.fresh(product.fields[field].type));
    if (p.kind == PatternKind::Product) {
      if (!p.rest && p.children.size() != facts(p).fields.size())
        error("type", p.span, "omitted product fields require '..'");
      std::vector<std::uint32_t> ordered;
      std::vector<int> orderedTypes;
      std::set<std::uint32_t> used;
      for (const auto &child : p.children) {
        auto foundField = std::find_if(
            facts(p).fields.begin(), facts(p).fields.end(), [&](auto field) {
              return product.fields[field].name == child.field;
            });
        if (foundField == facts(p).fields.end()) {
          error("name", child.span,
                "unknown pattern field '" + child.field + "'");
          continue;
        }
        if (!used.insert(*foundField).second)
          error("name", child.span, "duplicate pattern field");
        visibleField(type, *foundField, child.span);
        ordered.push_back(*foundField);
        orderedTypes.push_back(
            inference.fresh(product.fields[*foundField].type));
      }
      facts(p).fields = std::move(ordered);
      payloads = std::move(orderedTypes);
    }
  }
  if (payloads.size() != p.children.size()) {
    if (diagnostics.count() == diagnosticsBefore)
      error("type", p.span, "pattern payload count does not match");
    // Bind the names anyway so uses of them do not cascade.
    for (auto &child : p.children) {
      auto poisoned = inference.fresh();
      poisonedVariables.push_back(poisoned);
      pattern(child, poisoned, mode);
    }
    return;
  }
  for (std::size_t i = 0; i < payloads.size(); ++i)
    pattern(p.children[i], payloads[i], mode);
}

int Checker::match(Node &n, bool reachable) {
  int source = node(*n.children[0], reachable);
  // A pending field access may still name the scrutinee's instantiated type.
  if (inference.value(source) == Type::Unknown)
    fields(false);
  auto type = inference.value(source);
  while (checked.types->isView(type)) {
    type = checked.types->view(type).payload;
    ++facts(n).dereferences;
    source = inference.fresh(type);
  }
  matches.emplace_back(&n, source);
  auto mode = n.text == "take"  ? ParameterMode::Take
              : n.text == "mut" ? ParameterMode::Mut
                                : ParameterMode::Read;
  int result = inference.fresh(expectedTypes.contains(&n) ? expectedTypes.at(&n)
                                                          : Type::Never);
  const bool deferJoin = !expectedTypes.contains(&n);
  std::vector<Node *> tails;
  std::vector<int> bodies;
  std::vector<Span> spans;
  if (deferJoin)
    for (std::size_t i = 1; i < n.children.size(); ++i)
      markDeferrable(*n.children[i]->children.back());
  for (std::size_t i = 1; i < n.children.size(); ++i) {
    auto &arm = *n.children[i];
    scopes.emplace_back();
    pattern(arm.patterns[0], source, mode);
    if (arm.flag) {
      if (mode == ParameterMode::Take) {
        auto bodyBindings = scopes.back();
        scopes.back().clear();
        std::function<void(Pattern &)> guards = [&](Pattern &p) {
          if (p.kind == PatternKind::Binding || p.kind == PatternKind::At ||
              (p.kind == PatternKind::Rest && !p.text.empty())) {
            auto variable = patternVariables.at(&p);
            auto slot = local(p.text, variable, false, p.span);
            facts(p).guardSlot = slot;
            if (slot >= 0 &&
                !checked.types->isCopy(inference.value(variable))) {
              facts(*current).locals[slot].patternView = true;
              facts(*current).locals[slot].mode = ParameterMode::Read;
            }
          }
          for (auto &child : p.children)
            guards(child);
        };
        guards(arm.patterns[0]);
        inference.equal(node(*arm.children[0], reachable),
                        inference.fresh(Type::Bool), arm.children[0]->span,
                        true);
        scopes.back() = std::move(bodyBindings);
      } else {
        inference.equal(node(*arm.children[0], reachable),
                        inference.fresh(Type::Bool), arm.children[0]->span,
                        true);
      }
    }
    auto body = node(*arm.children.back(), reachable);
    if (!deferJoin)
      coerce(*arm.children.back(), body, result, arm.span);
    else {
      tails.push_back(arm.children.back().get());
      bodies.push_back(body);
      spans.push_back(arm.span);
    }
    scopes.pop_back();
  }
  if (deferJoin) {
    joinDeferred(tails, bodies);
    for (std::size_t i = 0; i < bodies.size(); ++i)
      result = inference.joined(result, bodies[i], spans[i]);
  }
  // Exhaustiveness is checked after type constraints have resolved.
  return result;
}

void Checker::resolvePatterns() {
  for (const auto &[pattern, variable] : patternVariables) {
    facts(*pattern).type = inference.value(variable);
    const auto &resolved = facts(*pattern);
    if (resolved.numeric &&
        !integerLiteralFits(*resolved.numeric, resolved.type, pointerBits()))
      error("type", pattern->span,
            "pattern literal is outside the " +
                std::string(checked.types->name(resolved.type)) + " range");
  }
}
int Checker::bindingPattern(Node &n, bool reachable) {
  if (n.children.empty()) {
    error("type", n.span, "destructuring requires an initializer");
    return inference.fresh(Type::Unit);
  }
  int input = node(*n.children[0], reachable);
  if (!n.annotation.empty())
    inference.equal(
        input,
        inference.fresh(annotation(n.annotation, n.span, current->owner)),
        n.span);
  if (n.children.size() > 1) {
    node(*n.children[1], reachable);
    if (facts(*n.children[1]).flow.normal)
      error("type", n.children[1]->span, "let-else branch must diverge");
  } else
    irrefutable.emplace_back(&n.patterns[0], input);
  std::function<void(const Pattern &)> shadow = [&](const Pattern &pattern) {
    if (pattern.kind == PatternKind::Binding ||
        pattern.kind == PatternKind::At || pattern.kind == PatternKind::Rest)
      scopes.back().erase(pattern.text);
    for (const auto &child : pattern.children)
      shadow(child);
  };
  shadow(n.patterns[0]);
  pattern(n.patterns[0], input, ParameterMode::Take);
  if (n.flag) {
    std::function<void(Pattern &)> mutableBindings = [&](Pattern &p) {
      if (facts(p).slot >= 0)
        facts(*current).locals[facts(p).slot].mutableBinding = true;
      for (auto &child : p.children)
        mutableBindings(child);
    };
    mutableBindings(n.patterns[0]);
  }
  return inference.fresh(Type::Unit);
}
int Checker::conditionalPattern(Node &n, bool reachable) {
  int input = node(*n.children[0], reachable);
  scopes.emplace_back();
  pattern(n.patterns[0], input, ParameterMode::Read);
  int yes = node(*n.children[1], reachable);
  scopes.pop_back();
  int no = n.children.size() > 2 ? node(*n.children[2], reachable)
                                 : inference.fresh(Type::Unit);
  if (n.children.size() > 2 && expectedTypes.contains(&n)) {
    auto result = inference.fresh(expectedTypes.at(&n));
    coerce(*n.children[1], yes, result, n.children[1]->span);
    coerce(*n.children[2], no, result, n.children[2]->span);
    return result;
  }
  return n.children.size() > 2
             ? join(*n.children[1], yes, *n.children[2], no, n.span)
             : inference.joined(yes, no, n.span);
}
} // namespace mettle
