#include "semantics/checker.h"
#include "support/limits.h"

namespace mettle {

void Checker::function(Function &f) {
  current = &f;
  scopes.clear();
  scopes.emplace_back();
  loops = 0;
  for (auto &p : f.parameters) {
    if (scopes.back().contains(p.name))
      error("name", p.span, "duplicate parameter '" + p.name + "'");
    auto t = annotation(p.annotation, p.span, f.owner);
    if (t == Type::Never)
      error("feature", p.span,
            "uninhabited parameters are not implemented in I02");
    auto mode = p.mode == "take"           ? ParameterMode::Take
                : p.mode == "read"         ? ParameterMode::Read
                : p.mode == "mut"          ? ParameterMode::Mut
                : checked.types->isCopy(t) ? ParameterMode::Value
                                           : ParameterMode::Read;
    auto slot = local(p.name, inference.fresh(t), false, p.span);
    if (slot >= 0)
      facts(f).locals[slot].mode = mode;
  }
  auto body = node(*f.body, true);
  if (facts(*f.body).flow.normal)
    inference.equal(body, functionVariables[&f], f.body->span, true);
  if (facts(f).diverges && f.annotation.empty())
    inference.equal(functionVariables[&f], inference.fresh(Type::Never),
                    f.span);
}
int Checker::node(Node &n, bool reachable) {
  auto unit = [&] { return inference.fresh(Type::Unit); };
  int result = inference.fresh();
  switch (n.kind) {
  case Kind::Integer:
    literal(n);
    result = inference.fresh(Type::I32);
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
    bool localName = false;
    for (const auto &scope : scopes)
      localName |= scope.contains(n.text);
    if (!localName && names.contains(n.text)) {
      error("feature", n.span, "function values are not implemented in I02");
      break;
    }
    auto found = lookup(n.text, n.span);
    result = found.variable;
    facts(n).slot = found.slot;
    break;
  }
  case Kind::Unary: {
    if (n.text == "read" || n.text == "mut" || n.text == "*") {
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
        if (!checked.types->isView(type))
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
    if (n.text == "-" && literalNode->kind == Kind::Integer) {
      literal(*literalNode, true);
      facts(n).number = facts(*literalNode).number;
      facts(n).foldedNegativeLiteral = true;
      for (auto *child = n.children[0].get();;
           child = child->children[0].get()) {
        nodeVariables[child] = inference.fresh(Type::I32);
        if (child == literalNode)
          break;
      }
      result = inference.fresh(Type::I32);
    } else {
      auto operand = node(*n.children[0], reachable);
      if (n.text == "-") {
        inference.equal(operand, inference.fresh(Type::I32), n.span, true);
        result = inference.fresh(Type::I32);
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
      } else {
        inference.equal(a, inference.fresh(Type::I32), n.span, true);
        inference.equal(b, inference.fresh(Type::I32), n.span, true);
        result = inference.fresh(Type::I32);
      }
    }
    break;
  }
  case Kind::Call:
    result = call(n, reachable);
    break;
  case Kind::Field: {
    auto base = node(*n.children[0], reachable);
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
    inference.equal(node(*n.children[0], reachable),
                    inference.fresh(Type::Bool), n.span, true);
    auto &condition = *n.children[0];
    auto literal = booleanLiteral(condition);
    bool yes = literal != false;
    bool no = literal != true;
    auto a =
        node(*n.children[1], reachable && facts(condition).flow.normal && yes);
    auto b = n.children.size() == 3
                 ? node(*n.children[2],
                        reachable && facts(condition).flow.normal && no)
                 : unit();
    result = inference.joined(a, b, n.span);
    if (!facts(n).flow.normal)
      result = inference.fresh(Type::Never);
    break;
  }
  case Kind::Binding: {
    auto t = n.children.empty() ? inference.fresh()
                                : node(*n.children[0], reachable);
    if (!n.annotation.empty()) {
      auto declared =
          inference.fresh(annotation(n.annotation, n.span, current->owner));
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
    if (place.kind != Kind::Name && place.kind != Kind::Field &&
        place.kind != Kind::Group &&
        !(place.kind == Kind::Unary && place.text == "*")) {
      error("type", place.span, "assignment requires a local place");
      break;
    }
    auto target = node(place, reachable);
    auto rhs = node(*n.children[1], reachable);
    inference.equal(rhs, target, n.span, true);
    if (n.text == "&=" || n.text == "|=" || n.text == "^=")
      integerOrBoolean.emplace_back(target, n.span);
    else if (n.text != "=")
      inference.equal(target, inference.fresh(Type::I32), n.span, true);
    result = unit();
    break;
  }
  case Kind::Return: {
    auto t = n.children.empty() ? unit() : node(*n.children[0], reachable);
    if (reachable && (n.children.empty() || facts(*n.children[0]).flow.normal))
      inference.equal(t, functionVariables[current], n.span, true);
    result = inference.fresh(Type::Never);
    break;
  }
  case Kind::While:
  case Kind::Loop:
    if (n.kind == Kind::While)
      inference.equal(node(*n.children[0], reachable),
                      inference.fresh(Type::Bool), n.span, true);
    ++loops;
    node(*n.children.back(),
         reachable &&
             (n.kind != Kind::While || facts(*n.children[0]).flow.normal) &&
             !(n.kind == Kind::While &&
               booleanLiteral(*n.children[0]) == false));
    --loops;
    result = facts(n).flow.normal ? unit() : inference.fresh(Type::Never);
    break;
  case Kind::Break:
  case Kind::Continue:
    if (!loops)
      error("type", n.span, "loop control outside a loop");
    result = inference.fresh(Type::Never);
    break;
  }
  nodeVariables[&n] = result;
  return result;
}
} // namespace mettle
