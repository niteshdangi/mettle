#include "semantics/checker.h"

namespace mettle {
int Checker::call(Node &n, bool reachable) {
  int result = inference.fresh();
  std::string name;
  std::size_t offset = 0;
  if (n.children[0]->kind == Kind::Field) {
    auto &member = *n.children[0];
    auto receiver = node(*member.children[0], reachable);
    fields(false);
    auto type = inference.value(receiver);
    while (checked.types->isView(type)) {
      type = checked.types->view(type).payload;
      ++facts(n).dereferences;
    }
    if (!checked.types->isProduct(type)) {
      error("type", n.span, "method receiver requires a resolved product type");
      return result;
    }
    name = checked.types->product(type).name + "." + member.text;
    facts(n).method = true;
    offset = 1;
  } else if (n.children[0]->kind == Kind::Name)
    name = n.children[0]->text;
  else {
    error("feature", n.span, "indirect calls are not implemented yet");
    return result;
  }
  bool shadowed = false;
  for (const auto &scope : scopes)
    shadowed |= scope.contains(name);
  if (shadowed) {
    error("type", n.span, "unresolved or non-callable function '" + name + "'");
    return result;
  }
  struct Argument {
    std::string_view name;
    Type type;
  };
  std::vector<Argument> signature;
  auto constructed = typeNames.find(name);
  if (constructed != typeNames.end() &&
      checked.types->isProduct(constructed->second)) {
    facts(n).constructor = true;
    result = inference.fresh(constructed->second);
    for (const auto &field : checked.types->product(constructed->second).fields)
      signature.push_back({field.name, field.type});
  } else {
    auto found = names.find(name);
    if (found == names.end()) {
      error("name", n.span,
            "unresolved or non-callable function '" + name + "'");
      return result;
    }
    facts(n).callee = static_cast<int>(found->second);
    auto &function = module.functions[found->second];
    if (function.destructor)
      error("ownership", n.span, "cannot invoke a destructor directly");
    facts(n).receiverReservation =
        facts(n).method && function.receiver == "mut";
    result = functionVariables[&function];
    for (const auto &parameter : function.parameters)
      signature.push_back(
          {parameter.name,
           annotation(parameter.annotation, parameter.span, function.owner)});
  }
  const auto count = n.children.size() - 1;
  if (count + offset != signature.size())
    error("type", n.span, "argument count does not match '" + name + "'");
  std::vector<bool> used(signature.size());
  if (offset)
    used[0] = true;
  bool named = false;
  for (std::size_t i = 0; i < count; ++i) {
    auto &argument = *n.children[i + 1];
    auto type = node(argument, reachable);
    fields(false);
    reachable &= facts(argument).flow.normal;
    std::size_t target = i + offset;
    if (!argument.name.empty()) {
      named = true;
      target = signature.size();
      for (std::size_t j = 0; j < signature.size(); ++j)
        if (signature[j].name == argument.name)
          target = j;
    } else if (named)
      error("type", argument.span,
            "positional arguments must precede named arguments");
    if (target >= signature.size()) {
      error("type", argument.span, "unknown or excess argument");
      facts(n).argumentOrder.push_back(0);
      continue;
    }
    if (used[target])
      error("type", argument.span, "duplicate argument");
    used[target] = true;
    facts(n).argumentOrder.push_back(target);
    if (!facts(n).constructor) {
      const auto &formal = module.functions[facts(n).callee].parameters[target];
      bool borrowed = formal.mode == "read" || formal.mode == "mut" ||
                      (formal.mode.empty() &&
                       !checked.types->isCopy(signature[target].type));
      auto actual = inference.value(type);
      if (borrowed && checked.types->isView(actual) &&
          checked.types->view(actual).payload == signature[target].type)
        type = inference.fresh(signature[target].type);
    }
    inference.equal(type, inference.fresh(signature[target].type),
                    argument.span, true);
  }
  return result;
}

void Checker::fields(bool final) {
  bool changed;
  do {
    changed = false;
    for (auto &request : fieldRequests) {
      if (request.resolved)
        continue;
      auto base = inference.value(request.base);
      if (base == Type::Unknown)
        continue;
      request.resolved = true;
      changed = true;
      if (base == Type::Never) {
        inference.equal(request.result, inference.fresh(Type::Never),
                        request.node->span);
        continue;
      }
      if (request.node->kind == Kind::Unary) {
        if (request.node->text == "*") {
          if (!checked.types->isView(base))
            error("type", request.node->span, "dereference requires a view");
          else
            inference.equal(request.result,
                            inference.fresh(checked.types->view(base).payload),
                            request.node->span);
        } else
          inference.equal(
              request.result,
              inference.fresh(checked.types->viewType(
                  base, request.node->text == "read" ? ParameterMode::Read
                                                     : ParameterMode::Mut)),
              request.node->span);
        continue;
      }
      while (checked.types->isView(base)) {
        base = checked.types->view(base).payload;
        ++facts(*request.node).dereferences;
      }
      if (!checked.types->isProduct(base)) {
        error("type", request.node->span,
              "field access requires a product value");
        continue;
      }
      const auto &product = checked.types->product(base);
      int index = -1;
      for (std::size_t i = 0; i < product.fields.size(); ++i)
        if (product.fields[i].name == request.node->text)
          index = static_cast<int>(i);
      if (index < 0) {
        error("name", request.node->span,
              "unknown field '" + request.node->text + "'");
        continue;
      }
      facts(*request.node).field = index;
      inference.equal(request.result,
                      inference.fresh(product.fields[index].type),
                      request.node->span);
    }
  } while (changed);
  if (!final)
    return;
  for (const auto &request : fieldRequests)
    if (!request.resolved)
      error("type", request.node->span,
            "cannot infer field source type; add ': Type'");
  fieldRequests.clear();
}
} // namespace mettle
