#include "semantics/checker.h"
#include "support/limits.h"
#include "syntax/lexer.h"
#include <array>

namespace mettle {

void Checker::requireUnsafe(Span span) {
  if (!unsafeDepth)
    error("unsafe", span,
          "operation requires an unsafe block or unsafe function");
}
void Checker::function(Function &f) {
  auto priorErrors = diagnostics.count();
  current = &f;
  guardedFeatures.clear();
  unsafeDepth = f.unsafeFunction ? 1 : 0;
  genericBindings(f);
  for (const auto &obligation : interfaceAssumptions())
    if (obligation.property == interfaces::Property::Interface)
      facts(f).interfaceBounds.emplace_back(obligation.subject,
                                            obligation.interfaceType);
    else if (obligation.property == interfaces::Property::Unpin)
      facts(f).unpinBounds.push_back(obligation.subject);
  if (genericEnvironment)
    facts(f).genericEqualities = genericEnvironment->equalities;
  scopes.clear();
  scopes.emplace_back();
  loopResults.clear();
  for (auto &p : f.parameters) {
    if (scopes.back().contains(p.name))
      error("name", p.span, "duplicate parameter '" + p.name + "'");
    auto t = annotation(p.annotation, p.span, f.owner);
    auto mode = p.mode == "take"           ? ParameterMode::Take
                : p.mode == "read"         ? ParameterMode::Read
                : p.mode == "mut"          ? ParameterMode::Mut
                : checked.types->isCopy(t) ? ParameterMode::Value
                                           : ParameterMode::Read;
    if (p.format && !formatMessage(t))
      error("signature", p.span,
            "a 'format' parameter must have type core::fmt::Message");
    auto variable = inference.fresh(t);
    if (p.format)
      formatVariables.insert(variable);
    auto slot = local(p.name, variable,
                      f.explicitReceiver && p.name == "self" &&
                          mode == ParameterMode::Take,
                      p.span);
    if (slot >= 0)
      facts(f).locals[slot].mode = mode;
  }
  if (diagnostics.count() != priorErrors)
    return;
  if (f.body.get())
    staticLocals();
  parameterDefaults(f);
  if (!f.body.get())
    return;
  if (!f.variadicCursor.empty()) {
    if (f.abi.empty())
      error("signature", f.variadicSpan,
            "a variadic cursor requires a foreign definition");
    if (scopes.back().contains(f.variadicCursor))
      error("name", f.variadicSpan, "duplicate variadic cursor binding");
    auto cursor = checked.types->structural(AggregateKind::VarArgs, {});
    facts(f).variadicCursor =
        local(f.variadicCursor, inference.fresh(cursor), true, f.variadicSpan);
  }
  constructor(f);
  if (!f.body.get())
    return;
  contextualize(*f.body, inference.value(functionVariables[&f]));
  auto body = node(*f.body, true);
  if (facts(*f.body).flow.normal)
    coerce(*f.body, body,
           f.constructor ? inference.fresh(Type::Unit) : functionVariables[&f],
           f.body->span);
  if (facts(f).diverges && f.annotation.empty())
    inference.equal(functionVariables[&f], inference.fresh(Type::Never),
                    f.span);
}
Type Checker::textLiteralType(const Node &n) {
  auto bytes = textLiteral(n.text, diagnostics, n.span);
  if (n.flag) {
    // Byte text is a static array of exactly its bytes.
    Type payload = checked.types->sliceType(Type::U8);
    if (bytes) {
      try {
        payload = checked.types->structural(
            AggregateKind::Array, {Type::U8},
            static_cast<std::uint32_t>(bytes->size()));
      } catch (const std::length_error &) {
        error("limit", n.span, "byte text exceeds the array length limit");
      }
      facts(n).text = std::move(*bytes);
    }
    return checked.types->viewType(payload, ParameterMode::Read,
                                   RegionId::Static);
  }
  auto text = typeNames.find("core::text::Text");
  if (text == typeNames.end()) {
    if (bytes)
      error("feature", n.span,
            "text literals require the library type core::text::Text");
    return Type::Unknown;
  }
  if (bytes)
    facts(n).text = std::move(*bytes);
  return checked.types->viewType(text->second, ParameterMode::Read,
                                 RegionId::Static);
}
int Checker::node(Node &n, bool reachable) {
  if (reusedNodes.erase(&n))
    return nodeVariables.at(&n);
  auto errorsBefore = diagnostics.count();
  auto result = checkNode(n, reachable);
  if (diagnostics.count() != errorsBefore)
    poisonedVariables.push_back(result);
  return result;
}
int Checker::checkNode(Node &n, bool reachable) {
  auto unit = [&] { return inference.fresh(Type::Unit); };
  int result = inference.fresh();
  switch (n.kind) {
  case Kind::Assembly:
    result = assemblyExpression(n, reachable);
    break;
  case Kind::FeatureTest:
    result = featureTest(n);
    break;
  case Kind::Unsafe: {
    auto depth = unsafeDepth;
    ++unsafeDepth;
    result = node(*n.children[0], reachable);
    unsafeDepth = depth;
    break;
  }
  case Kind::Integer:
  case Kind::Floating:
    result = inference.numeric(n.kind == Kind::Floating, literal(n));
    break;
  case Kind::Cast: {
    node(*n.children[0], reachable);
    auto target = annotation(n.annotation, n.span, current->owner);
    result = inference.fresh(target);
    break;
  }
  case Kind::Character: {
    result = inference.fresh(n.flag ? Type::U8 : Type::Char);
    auto value = characterLiteral(n.text, n.flag, diagnostics, n.span);
    if (value)
      facts(n).number = static_cast<std::int32_t>(*value);
    break;
  }
  case Kind::Text:
    if (auto type = textLiteralType(n); type != Type::Unknown)
      result = inference.fresh(type);
    break;
  case Kind::Boolean:
    result = inference.fresh(Type::Bool);
    facts(n).number = n.text == "true";
    break;
  case Kind::Unit:
    result = unit();
    break;
  case Kind::Group:
    result = node(*n.children[0], reachable);
    break;
  case Kind::Name: {
    if (genericEnvironment) {
      auto parameter = genericEnvironment->names.find(n.text);
      if (parameter != genericEnvironment->names.end() &&
          checked.types->isConstant(parameter->second)) {
        facts(n).constantParameter = parameter->second;
        result = inference.fresh(
            checked.types->parameter(parameter->second).valueType);
        break;
      }
    }
    bool localName = false;
    for (const auto &scope : scopes)
      localName |= scope.contains(n.text);
    if (!localName)
      if (auto primitive = machineValue(n)) {
        result = *primitive;
        break;
      }
    if (!localName)
      if (auto constant = associatedConstant(n);
          constant && checked.types->isConstant(*constant)) {
        facts(n).constantParameter = *constant;
        result = inference.fresh(checked.types->parameter(*constant).valueType);
        break;
      }
    if (!localName)
      if (auto generic = genericUnitVariant(n)) {
        result = *generic;
        break;
      }
    if (!localName)
      if (auto variant = variantCall(n, n.text, reachable)) {
        result = *variant;
        break;
      }
    if (!localName &&
        names.contains(callableName(n.text, current->owner, n.span))) {
      result = functionValue(
          n, names.at(callableName(n.text, current->owner, n.span)));
      break;
    }
    auto found = lookup(n.text, n.span);
    result = found.variable;
    facts(n).slot = found.slot;
    if (formatVariables.contains(found.variable) &&
        !permittedRecipes.contains(&n))
      error("type", n.span,
            "a 'format' parameter can only be forwarded to another 'format' "
            "parameter or used as a method receiver");
    else if (formatVariables.contains(found.variable) &&
             closureFunctions.contains(current))
      error("type", n.span, "a closure cannot capture a 'format' parameter");
    break;
  }
  case Kind::Unary: {
    if (n.text == "read" || n.text == "mut" || n.text == "*") {
      if (n.text == "mut")
        requireMutablePlace(*n.children[0]);
      auto operand = node(*n.children[0], reachable);
      fields(false);
      auto type = inference.value(operand);
      if (type == Type::Never) {
        result = operand;
        break;
      }
      if (type == Type::Unknown) {
        fieldRequests.push_back({&n, operand, result});
        break;
      }
      if (n.text == "*") {
        if (checked.types->isPointer(type)) {
          requireUnsafe(n.span);
          result = inference.fresh(checked.types->pointer(type).payload);
        } else if (!checked.types->isView(type))
          error("type", n.span, "dereference requires a view");
        else
          result = inference.fresh(checked.types->view(type).payload);
      } else
        result = inference.fresh(checked.types->viewType(
            type, n.text == "read" ? ParameterMode::Read : ParameterMode::Mut));
      break;
    }
    if (n.text == "take") {
      result = node(*n.children[0], reachable);
      break;
    }
    auto *literalNode = n.children[0].get();
    while (literalNode->kind == Kind::Group)
      literalNode = literalNode->children[0].get();
    if (n.text == "-" && (literalNode->kind == Kind::Integer ||
                          literalNode->kind == Kind::Floating)) {
      auto suffix = literal(*literalNode, true);
      facts(n).number = facts(*literalNode).number;
      facts(n).numeric = facts(*literalNode).numeric;
      facts(n).foldedNegativeLiteral = true;
      result = inference.numeric(literalNode->kind == Kind::Floating, suffix);
      for (auto *child = n.children[0].get();;
           child = child->children[0].get()) {
        nodeVariables[child] = result;
        if (child == literalNode)
          break;
      }
    } else {
      auto operand = node(*n.children[0], reachable);
      if (auto overloaded = operatorCall(n, operand)) {
        result = *overloaded;
        break;
      }
      if (n.text == "-") {
        numericOperations.push_back({operand, n.span, "negate"});
        result = operand;
      } else {
        integerOrBoolean.emplace_back(operand, n.span);
        result = operand;
      }
    }
    break;
  }
  case Kind::Binary: {
    auto a = node(*n.children[0], reachable);
    auto literal = booleanLiteral(*n.children[0]);
    bool shortcut = (n.text == "&&" && literal == false) ||
                    (n.text == "||" && literal == true);
    auto b = node(*n.children[1],
                  reachable && facts(*n.children[0]).flow.normal && !shortcut);
    if (auto overloaded = operatorCall(n, a, b)) {
      result = *overloaded;
      break;
    }
    if (n.text == "&&" || n.text == "||") {
      inference.equal(a, inference.fresh(Type::Bool), n.span, true);
      inference.equal(b, inference.fresh(Type::Bool), n.span, true);
      result = inference.fresh(Type::Bool);
    } else if (n.text == "==" || n.text == "!=" || n.text == "<" ||
               n.text == ">" || n.text == "<=" || n.text == ">=") {
      comparisons.emplace_back(inference.joined(a, b, n.span), n.span);
      result = inference.fresh(Type::Bool);
    } else {
      if (n.text == "&" || n.text == "|" || n.text == "^") {
        result = inference.joined(a, b, n.span);
        integerOrBoolean.emplace_back(result, n.span);
      } else if (n.text == "<<" || n.text == ">>") {
        numericOperations.push_back({a, n.span, "integer"});
        numericOperations.push_back({b, n.span, "integer"});
        result = a;
      } else {
        result = inference.joined(a, b, n.span);
        numericOperations.push_back({result, n.span, "arithmetic"});
      }
    }
    break;
  }
  case Kind::Call:
    result = call(n, reachable);
    break;
  case Kind::Closure:
    result = closure(n, reachable);
    break;
  case Kind::None:
  case Kind::Variant:
  case Kind::Throw:
  case Kind::Try:
  case Kind::Capture:
    result = sumExpression(n, reachable);
    break;
  case Kind::Match:
    result = match(n, reachable);
    break;
  case Kind::Tuple:
  case Kind::Array:
  case Kind::Index:
  case Kind::Range:
  case Kind::For:
  case Kind::Coalesce:
    result = aggregate(n, reachable);
    break;
  case Kind::Arm:
    throw std::runtime_error("match arm checked outside its match");
  case Kind::Field: {
    facts(n).unsafeContext = unsafeDepth != 0;
    auto base = node(*n.children[0], reachable);
    if (n.flag) {
      auto components =
          inference.components(base, AggregateKind::Optional, n.span);
      facts(n).optional = true;
      auto payload = inference.fresh();
      if (!components.empty())
        fieldRequests.push_back({&n, components[0], payload});
      result = inference.composite(AggregateKind::Optional, {payload});
    } else
      fieldRequests.push_back({&n, base, result});
    break;
  }
  case Kind::Block: {
    scopes.emplace_back();
    bool live = reachable;
    result = facts(n).flow.normal ? unit() : inference.fresh(Type::Never);
    for (std::size_t i = 0; i < n.children.size(); ++i) {
      auto &child = *n.children[i];
      auto t = node(child, live);
      if (i + 1 == n.children.size() && !isStatement(child.kind) &&
          !child.semicolon && facts(n).flow.normal)
        result = t;
      live &= facts(child).flow.normal;
    }
    scopes.pop_back();
    break;
  }
  case Kind::If: {
    if (!n.patterns.empty()) {
      result = conditionalPattern(n, reachable);
      break;
    }
    inference.equal(node(*n.children[0], reachable),
                    inference.fresh(Type::Bool), n.span, true);
    auto &condition = *n.children[0];
    auto literal = booleanLiteral(condition);
    bool yes = literal != false;
    bool no = literal != true;
    const bool deferJoin =
        n.children.size() == 3 && !expectedTypes.contains(&n);
    if (deferJoin) {
      markDeferrable(*n.children[1]);
      markDeferrable(*n.children[2]);
    }
    auto savedFeatures = guardedFeatures;
    if (condition.kind == Kind::FeatureTest)
      guardedFeatures.insert(condition.text);
    auto a =
        node(*n.children[1], reachable && facts(condition).flow.normal && yes);
    guardedFeatures = std::move(savedFeatures);
    auto b = n.children.size() == 3
                 ? node(*n.children[2],
                        reachable && facts(condition).flow.normal && no)
                 : unit();
    if (deferJoin) {
      const std::array<Node *, 2> tails{n.children[1].get(),
                                        n.children[2].get()};
      const std::array<int, 2> types{a, b};
      joinDeferred(tails, types);
    }
    if (n.children.size() == 3 && expectedTypes.contains(&n)) {
      result = inference.fresh(expectedTypes.at(&n));
      coerce(*n.children[1], a, result, n.children[1]->span);
      coerce(*n.children[2], b, result, n.children[2]->span);
    } else
      result = n.children.size() == 3
                   ? join(*n.children[1], a, *n.children[2], b, n.span)
                   : inference.joined(a, b, n.span);
    if (!facts(n).flow.normal)
      result = inference.fresh(Type::Never);
    break;
  }
  case Kind::Binding: {
    if (!n.patterns.empty()) {
      result = bindingPattern(n, reachable);
      break;
    }
    auto annotationErrors = reportedErrors;
    auto declaredType = n.annotation.empty()
                            ? Type::Unknown
                            : annotation(n.annotation, n.span, current->owner);
    bool annotationFailed = reportedErrors != annotationErrors;
    if (!n.children.empty() && !n.annotation.empty())
      contextualize(*n.children[0], declaredType);
    auto t = n.children.empty() ? inference.fresh()
                                : node(*n.children[0], reachable);
    if (!n.annotation.empty()) {
      auto declared = inference.fresh(declaredType);
      if (annotationFailed)
        poisonedVariables.push_back(declared);
      if (!n.children.empty())
        coerce(*n.children[0], t, declared, n.span);
      else
        inference.equal(t, declared, n.span, true);
      t = declared;
    }
    if (n.text != "_")
      facts(n).slot = local(n.text, t, n.flag, n.span);
    result = unit();
    break;
  }
  case Kind::Assign: {
    auto &place = *n.children[0];
    auto *written = &place;
    while (written->kind == Kind::Group)
      written = written->children[0].get();
    if (n.text == "=" && written->kind == Kind::Field)
      facts(*written).writeOnly = true;
    requireMutablePlace(place);
    if (place.kind != Kind::Name && place.kind != Kind::Field &&
        place.kind != Kind::Index && place.kind != Kind::Group &&
        !(place.kind == Kind::Unary && place.text == "*")) {
      error("type", place.span, "assignment requires a local place");
      break;
    }
    auto target = node(place, reachable);
    auto rhs = node(*n.children[1], reachable);
    if (n.text != "=")
      if (auto overloaded = operatorCall(n, target, rhs)) {
        result = *overloaded;
        break;
      }
    if (n.text != "<<=" && n.text != ">>=")
      coerce(*n.children[1], rhs, target, n.span);
    if (n.text == "&=" || n.text == "|=" || n.text == "^=")
      integerOrBoolean.emplace_back(target, n.span);
    else if (n.text == "<<=" || n.text == ">>=") {
      numericOperations.push_back({target, n.span, "integer"});
      numericOperations.push_back({rhs, n.span, "integer"});
    } else if (n.text != "=")
      numericOperations.push_back({target, n.span, "arithmetic"});
    result = unit();
    break;
  }
  case Kind::Return: {
    if (!n.children.empty())
      contextualize(*n.children[0],
                    inference.value(functionVariables[current]));
    auto t = n.children.empty() ? unit() : node(*n.children[0], reachable);
    if (reachable &&
        (n.children.empty() || facts(*n.children[0]).flow.normal)) {
      auto expected = current->constructor ? inference.fresh(Type::Unit)
                                           : functionVariables[current];
      if (n.children.empty())
        inference.equal(t, expected, n.span, true);
      else
        coerce(*n.children[0], t, expected, n.span);
    }
    result = inference.fresh(Type::Never);
    break;
  }
  case Kind::While:
  case Kind::Loop:
    result = loop(n, reachable);
    break;
  case Kind::Break:
  case Kind::Continue:
    result = transfer(n, reachable);
    break;
  }
  if (n.kind != Kind::Try && n.kind != Kind::Capture && n.kind != Kind::Closure)
    for (const auto &child : n.children) {
      auto effect = facts(*child).effect;
      if (effect == Type::Unknown)
        continue;
      if (facts(n).effect != Type::Unknown && facts(n).effect != effect)
        error("effects", n.span,
              "expression combines incompatible typed failure types");
      else
        facts(n).effect = effect;
    }
  nodeVariables[&n] = result;
  return result;
}
} // namespace mettle
