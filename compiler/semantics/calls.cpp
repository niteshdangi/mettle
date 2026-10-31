#include "semantics/checker.h"
#include "support/path.h"
#include "types/layout.h"

namespace mettle {
bool Checker::formatMessage(Type type) const {
  return checked.types->isProduct(type) &&
         checked.types->product(type).name == "core::fmt::Message";
}
// Recipes may reach only `format` parameters: an f-string, a forwarded
// `format` parameter, or any other expression, which becomes the single hole
// of a recipe (a Text or String argument, say). Nothing else can hold one.
void Checker::formatArguments(Node &n, const Function &callee,
                              std::size_t offset) {
  for (std::size_t i = 1; i < n.children.size(); ++i) {
    auto &argument = *n.children[i];
    std::size_t target = i - 1 + offset;
    if (!argument.name.empty())
      for (std::size_t j = 0; j < callee.parameters.size(); ++j)
        if (callee.parameters[j].name == argument.name)
          target = j;
    if (target >= callee.parameters.size() || !callee.parameters[target].format)
      continue;
    if (argument.label == formatRecipeLabel) {
      permittedRecipes.insert(&argument);
      continue;
    }
    if (argument.kind == Kind::Name) {
      bool forwarded = false;
      for (auto scope = scopes.rbegin(); scope != scopes.rend(); ++scope)
        if (auto found = scope->find(argument.text); found != scope->end()) {
          forwarded = formatVariables.contains(found->second.variable);
          break;
        }
      if (forwarded) {
        permittedRecipes.insert(&argument);
        continue;
      }
    }
    if (!n.children[i].owns())
      continue;
    const auto span = argument.span;
    auto label = std::move(argument.name);
    argument.name.clear();
    std::vector<std::unique_ptr<Node>> holes, pieces;
    for (int piece = 0; piece < 2; ++piece) {
      auto empty = std::make_unique<Node>();
      empty->kind = Kind::Text;
      empty->span = {span.begin, span.begin, span.source};
      empty->text = "\"\"";
      pieces.push_back(std::move(empty));
    }
    holes.push_back(n.children[i].release());
    auto recipe = formatRecipe(span, std::move(holes), std::move(pieces));
    recipe->name = std::move(label);
    permittedRecipes.insert(recipe.get());
    n.children[i] = NodeOwner(std::move(recipe));
  }
}
int Checker::call(Node &n, bool reachable) {
  if (n.label == formatRecipeLabel && !permittedRecipes.contains(&n)) {
    error("type", n.span,
          "an f-string can only be passed to a 'format' parameter");
    return inference.fresh();
  }
  bool localCallee = false;
  for (const auto &scope : scopes)
    localCallee |= n.children[0]->kind == Kind::Name &&
                   n.children[0]->annotation.form != TypeForm::Projection &&
                   scope.contains(n.children[0]->text);
  if (n.children[0]->kind == Kind::Name &&
      n.children[0]->annotation.form != TypeForm::Projection &&
      staticName(n.children[0]->text, n.children[0]->span))
    localCallee = true;
  if (localCallee ||
      (n.children[0]->kind != Kind::Name && n.children[0]->kind != Kind::Field))
    return indirectCall(n, reachable);
  int result = inference.fresh();
  std::string name;
  std::size_t offset = 0;
  bool directDestructor = false;
  if (n.children[0]->kind == Kind::Field) {
    auto &member = *n.children[0];
    if (member.children[0]->kind == Kind::Name)
      permittedRecipes.insert(member.children[0].get());
    auto receiverErrors = diagnostics.items.size();
    auto receiver = node(*member.children[0], reachable);
    facts(member).effect = facts(*member.children[0]).effect;
    if (member.flag) {
      auto components =
          inference.components(receiver, AggregateKind::Optional, n.span);
      facts(n).optional = true;
      if (!components.empty())
        receiver = components[0];
    }
    fields(false);
    auto type = inference.value(receiver);
    auto before = diagnostics.items.size();
    auto selected = receiverMethod(type, n);
    if (selected) {
      name = checked.functions[*selected].canonicalName;
      facts(n).method = true;
      offset = 1;
      directDestructor = module.functions[*selected].destructor;
    } else {
      if (diagnostics.items.size() != before)
        return result;
      if (auto primitive = machineCall(n, reachable, receiver))
        return *primitive;
      while (checked.types->isView(type)) {
        type = checked.types->view(type).payload;
        ++facts(n).dereferences;
      }
      if (!checked.types->isProduct(type)) {
        // A receiver that already failed to check is not reported again.
        if (diagnostics.items.size() == receiverErrors)
          error("type", n.span, "unresolved method for this receiver type");
        return result;
      }
      const auto &product = checked.types->product(type);
      auto inherent =
          (product.genericOrigin == Type::Unknown
               ? product.name
               : checked.types->product(product.genericOrigin).name) +
          "." + member.text;
      for (std::size_t field = 0;
           !names.contains(inherent) && field < product.fields.size(); ++field)
        if (product.fields[field].name == member.text) {
          auto callable = product.fields[field].type;
          while (checked.types->isView(callable))
            callable = checked.types->view(callable).payload;
          if (!checked.types->isCallable(callable))
            continue;
          visibleField(type, field, n.span);
          facts(member).field = static_cast<int>(field);
          facts(member).dereferences = facts(n).dereferences;
          facts(n).dereferences = 0;
          auto variable = inference.fresh(product.fields[field].type);
          nodeVariables[&member] = variable;
          auto result = indirectCall(n, reachable, variable);
          return facts(n).optional
                     ? inference.composite(AggregateKind::Optional, {result})
                     : result;
        }
      name = (product.genericOrigin == Type::Unknown
                  ? product.name
                  : checked.types->product(product.genericOrigin).name) +
             "." + member.text;
      directDestructor =
          member.text == "drop" && checked.types->product(type).hasDestructor;
      facts(n).method = true;
      offset = 1;
    }
  } else if (n.children[0]->kind == Kind::Name) {
    const auto &qualified = n.children[0]->annotation;
    if (qualified.form == TypeForm::Projection &&
        qualified.elements.size() == 2) {
      auto self = annotation(qualified.elements[0], n.span, current->owner);
      auto interface =
          interfaceBound(qualified.elements[1], n.span, current->owner);
      if (!interfaceObligation(self, interface, n.span))
        return result;
      const auto &definition =
          checked.interfaceData
              ->definitions[checked.types->erased(interface).declaration];
      auto method = std::find_if(
          definition.methods.begin(), definition.methods.end(),
          [&](const auto &method) { return method.name == qualified.name; });
      if (method == definition.methods.end()) {
        error("name", n.span, "interface has no such associated function");
        return result;
      }
      facts(n).interfaceSelf = self;
      facts(n).interfaceType = interface;
      facts(n).interfaceMethod =
          static_cast<int>(method - definition.methods.begin());
      name = checked.functions[method->function].canonicalName;
    } else
      name = callableName(n.children[0]->text, current->owner, n.span);
    const auto &spelling = n.children[0]->text;
    auto separator = spelling.rfind("::");
    if (separator != std::string::npos &&
        spelling.substr(separator + 2) == "drop") {
      auto owner =
          typeName(spelling.substr(0, separator), n.span, current->owner);
      auto type = typeNames.find(owner);
      directDestructor = type != typeNames.end() &&
                         checked.types->isProduct(type->second) &&
                         checked.types->product(type->second).hasDestructor;
    }
  } else {
    error("feature", n.span, "indirect calls are not implemented yet");
    return result;
  }
  if (directDestructor) {
    error("ownership", n.span, "cannot invoke a destructor directly");
    return result;
  }
  bool shadowed = false;
  for (const auto &scope : scopes)
    shadowed |= n.children[0]->kind == Kind::Name &&
                n.children[0]->annotation.form != TypeForm::Projection &&
                scope.contains(n.children[0]->text);
  if (shadowed) {
    error("type", n.span,
          "unresolved or non-callable function '" +
              displayPath(n.children[0]->text) + "'");
    return result;
  }
  if (n.children[0]->kind == Kind::Name)
    if (auto generic = genericConstruction(n, reachable, name))
      return *generic;
  if (n.children[0]->kind == Kind::Name)
    if (auto variant = variantCall(n, n.children[0]->text, reachable))
      return *variant;
  struct Argument {
    std::string_view name;
    Type type;
  };
  std::vector<Argument> signature;
  auto constructed = typeNames.find(name);
  if (constructed != typeNames.end() &&
      checked.types->isSum(constructed->second)) {
    if (!names.contains(name)) {
      error("type", n.span, "enum construction requires a named variant");
      return result;
    }
    constructed = typeNames.end();
  }
  if (constructed != typeNames.end() &&
      checked.types->isProduct(constructed->second)) {
    auto origin = checked.types->product(constructed->second).genericOrigin;
    if (origin == Type::Unknown)
      origin = constructed->second;
    if (constructors.contains(origin)) {
      GenericEnvironment environment;
      return genericCustomConstruction(n, reachable, origin,
                                       constructed->second, environment,
                                       constructed->second != origin);
    }
  }
  if (constructed != typeNames.end() &&
      checked.types->isProduct(constructed->second)) {
    facts(n).constructor = true;
    result = inference.fresh(constructed->second);
    std::size_t index = 0;
    for (const auto &field :
         checked.types->product(constructed->second).fields) {
      if (!checked.types->product(constructed->second).layout.unionType)
        visibleField(constructed->second, index, n.span);
      ++index;
      signature.push_back({field.name, field.type});
    }
    if (checked.types->product(constructed->second).layout.unionType) {
      if (n.children.size() != 2 || n.children[1]->name.empty()) {
        error("type", n.span,
              "union construction requires exactly one named field");
        return result;
      }
      auto selected = std::find_if(
          signature.begin(), signature.end(),
          [&](const auto &field) { return field.name == n.children[1]->name; });
      if (selected == signature.end()) {
        error("name", n.span, "unknown union constructor field");
        return result;
      }
      facts(n).field = selected - signature.begin();
      visibleField(constructed->second, facts(n).field, n.span);
      auto field = *selected;
      signature = {field};
    }
  } else {
    auto found = names.find(name);
    if (found == names.end()) {
      if (auto primitive = targetCall(n, reachable))
        return *primitive;
      if (auto primitive = machineCall(n, reachable))
        return *primitive;
      error("name", n.span,
            "unresolved or inaccessible function '" +
                displayPath(n.children[0]->text) + "'" +
                (current->owner.empty() &&
                         n.children[0]->text.starts_with("Self::")
                     ? "; 'Self' is only available inside a type or extend "
                       "body"
                     : ""));
      return result;
    }
    facts(n).callee = static_cast<int>(found->second);
    formatArguments(n, module.functions[found->second], offset);
    if (const auto &declared = module.functions[found->second];
        !declared.body.get() && !declared.foreignDeclaration &&
        !declared.interfaceOwner.empty() && declared.implementation < 0 &&
        facts(n).interfaceMethod < 0) {
      error("type", n.span,
            "an interface method without a body cannot be called through the "
            "interface name; call it as a method or as 'T.(" +
                displayPath(declared.interfaceOwner) + ")." +
                declared.name.substr(declared.name.rfind('.') + 1) + "'");
      return result;
    }
    requireFeatures(facts(module.functions[found->second]).targetFeatures,
                    n.span);
    // Compiler-built format recipes call the unsafe recipe constructors.
    if (module.functions[found->second].unsafeFunction &&
        n.label != formatInternalLabel && n.label != formatRecipeLabel)
      requireUnsafe(n.span);
    if (auto generic = genericCall(n, reachable, found->second, offset))
      return *generic;
    auto runtimeArgument = [](const GenericArgument &argument) {
      return argument.region.empty();
    };
    if (std::any_of(n.children[0]->genericArguments.begin(),
                    n.children[0]->genericArguments.end(), runtimeArgument) ||
        std::any_of(n.children[0]->ownerGenericArguments.begin(),
                    n.children[0]->ownerGenericArguments.end(),
                    runtimeArgument))
      error("type", n.span, "function does not accept generic arguments");
    auto &function = module.functions[found->second];
    if (facts(n).method && function.receiver == "mut")
      requireMutablePlace(*n.children[0]->children[0]);
    if (facts(n).interfaceMethod < 0 &&
        !checked.symbols->accessible(function.span,
                                     checked.symbols->moduleOf(n.span)))
      error("name", n.span,
            "private or restricted function '" + displayPath(function.name) +
                "' is inaccessible");
    if (!function.error.empty()) {
      facts(n).effect =
          annotation(function.error, function.span, function.owner);
      if (!effectContext)
        error("effects", n.span, "throwing call requires try or capture");
    }
    if (facts(n).method && function.receiver == "static")
      error("type", n.span,
            "static associated function requires a type-qualified call");
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
  bool variadic =
      !facts(n).constructor && module.functions[facts(n).callee].variadic;
  if (variadic) {
    requireUnsafe(n.span);
    while (signature.size() < count + offset)
      signature.push_back({"", Type::Unknown});
  }
  if (facts(n).constructor && count + offset != signature.size())
    error("type", n.span,
          "argument count does not match '" + displayPath(name) + "'");
  std::vector<bool> used(signature.size());
  if (offset && !used.empty())
    used[0] = true;
  bool named = false, misbound = false;
  for (std::size_t i = 0; i < count; ++i) {
    auto &argument = *n.children[i + 1];
    auto contextualTarget = i + offset;
    if (!argument.name.empty())
      for (std::size_t j = 0; j < signature.size(); ++j)
        if (signature[j].name == argument.name)
          contextualTarget = j;
    if (contextualTarget < signature.size())
      contextualize(argument, signature[contextualTarget].type);
    if (!facts(n).constructor &&
        contextualTarget <
            module.functions[facts(n).callee].parameters.size() &&
        module.functions[facts(n).callee].parameters[contextualTarget].mode ==
            "mut")
      requireMutablePlace(argument);
    auto type = node(argument, reachable);
    fields(false);
    reachable &= facts(argument).flow.normal;
    std::size_t target = i + offset;
    bool misordered = false;
    if (!argument.name.empty()) {
      named = true;
      target = signature.size();
      for (std::size_t j = 0; j < signature.size(); ++j)
        if (signature[j].name == argument.name)
          target = j;
    } else if (named) {
      misbound = misordered = true;
      error("type", argument.span,
            "positional arguments must precede named arguments");
    }
    if (target >= signature.size()) {
      misbound = true;
      error("type", argument.span, "unknown or excess argument");
      facts(n).argumentOrder.push_back(0);
      continue;
    }
    if (used[target] && !misordered) {
      misbound = true;
      error("type", argument.span, "duplicate argument");
    }
    used[target] = true;
    facts(n).argumentOrder.push_back(target);
    if (variadic &&
        target >= module.functions[facts(n).callee].parameters.size()) {
      auto actual = inference.value(type);
      if (!cCompatible(*checked.types, actual))
        error("signature", argument.span,
              "variadic argument has no C-compatible representation");
      if (!checked.types->isCopy(actual) &&
          (argument.kind == Kind::Name || argument.kind == Kind::Field))
        error("ownership", argument.span,
              "variadic non-Copy arguments require explicit take");
      continue;
    }
    auto *argumentValue = &argument;
    while (argumentValue->kind == Kind::Group)
      argumentValue = argumentValue->children[0].get();
    if (facts(n).callee >= 0 &&
        static_cast<std::size_t>(facts(n).callee) < module.functions.size() &&
        target < module.functions[facts(n).callee].parameters.size() &&
        module.functions[facts(n).callee].parameters[target].mode == "take" &&
        !(argumentValue->kind == Kind::Unary && argumentValue->text == "take"))
      diagnoseBorrowedMatchMove(argument, type);
    if (!facts(n).constructor) {
      const auto &formal = module.functions[facts(n).callee].parameters[target];
      bool borrowed = formal.mode == "read" || formal.mode == "mut" ||
                      (formal.mode.empty() &&
                       !checked.types->isCopy(signature[target].type));
      auto mode =
          formal.mode == "mut" ? ParameterMode::Mut : ParameterMode::Read;
      if (borrowed &&
          borrowCoercion(argument, type, signature[target].type, mode))
        continue;
      auto actual = inference.value(type);
      if (borrowed && checked.types->isView(actual) &&
          checked.types->view(actual).payload == signature[target].type)
        type = inference.fresh(signature[target].type);
    }
    coerce(argument, type, inference.fresh(signature[target].type),
           argument.span);
  }
  if (!facts(n).constructor)
    completeArguments(n, module.functions[facts(n).callee], used, !misbound);
  if (facts(n).optional)
    return inference.composite(AggregateKind::Optional, {result});
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
      if (request.origin != Type::Unknown) {
        const auto &instance = checked.types->isProduct(base)
                                   ? checked.types->product(base)
                                   : checked.types->product(request.origin);
        if (!checked.types->isProduct(base) ||
            (base != request.origin &&
             instance.genericOrigin != request.origin))
          error("type", request.node->span,
                "generic variant '" + request.node->text +
                    "' does not construct the expected type");
        continue;
      }
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
      if (request.node->kind == Kind::Index) {
        while (checked.types->isView(base)) {
          base = checked.types->view(base).payload;
          ++facts(*request.node).dereferences;
        }
        const bool sliced = request.node->children[1]->kind == Kind::Range;
        if (sliced) {
          // A subslice is the unsized place `[T]`; `read`/`mut` borrow it.
          auto slice = base;
          if (!checked.types->isSlice(base) && checked.types->isProduct(base) &&
              checked.types->product(base).kind == AggregateKind::Array) {
            const auto &array = checked.types->product(base);
            slice = checked.types->sliceType(array.components[0]);
            facts(*request.node).rangeArrayCount =
                array.arrayCount == Type::Unknown
                    ? checked.types->constant(Type::I32, array.fields.size())
                    : array.arrayCount;
          } else if (!checked.types->isSlice(base)) {
            error("type", request.node->span,
                  "range indexing requires an array, slice or a type "
                  "implementing core.ops.IndexRange");
            continue;
          }
          inference.equal(request.result, inference.fresh(slice),
                          request.node->span);
          facts(*request.node).readView =
              checked.types->viewType(slice, ParameterMode::Read);
          facts(*request.node).mutView =
              checked.types->viewType(slice, ParameterMode::Mut);
          continue;
        }
        if (checked.types->isSlice(base)) {
          auto element = checked.types->slice(base).element;
          inference.equal(request.result, inference.fresh(element),
                          request.node->span);
          facts(*request.node).readView =
              checked.types->viewType(element, ParameterMode::Read);
          facts(*request.node).mutView =
              checked.types->viewType(element, ParameterMode::Mut);
          continue;
        }
        if (!checked.types->isProduct(base) ||
            checked.types->product(base).kind != AggregateKind::Array) {
          error("type", request.node->span, "indexing requires an array");
          continue;
        }
        const auto &array = checked.types->product(base);
        inference.equal(request.result, inference.fresh(array.components[0]),
                        request.node->span);
        facts(*request.node).readView =
            checked.types->viewType(array.components[0], ParameterMode::Read);
        facts(*request.node).mutView =
            checked.types->viewType(array.components[0], ParameterMode::Mut);
        const auto &index = *request.node->children[1];
        if (index.kind == Kind::Integer && array.arrayCount == Type::Unknown) {
          auto value = facts(index).numeric.value_or(
              integerLiteral(facts(index).number));
          if (value.negative || value.magnitude[1] ||
              value.magnitude[0] >= array.fields.size())
            error("type", index.span, "array index is out of bounds");
          else
            facts(*request.node).field = static_cast<int>(value.magnitude[0]);
        }
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
      if (product.layout.unionType && !facts(*request.node).writeOnly &&
          !facts(*request.node).unsafeContext)
        error("unsafe", request.node->span,
              "reading a union field requires unsafe");
      if (checked.types->isSum(base)) {
        error("type", request.node->span,
              "variant payload requires pattern matching");
        continue;
      }
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
      visibleField(base, static_cast<std::size_t>(index), request.node->span);
      inference.equal(request.result,
                      inference.fresh(product.fields[index].type),
                      request.node->span);
    }
  } while (changed);
  if (!final)
    return;
  std::set<int> poisonedRoots;
  for (auto variable : poisonedVariables)
    poisonedRoots.insert(inference.representative(variable));
  for (const auto &request : fieldRequests)
    if (!request.resolved && !inference.depends(request.base, poisonedRoots))
      error("type", request.node->span,
            request.origin != Type::Unknown
                ? "cannot infer generic arguments of variant '" +
                      request.node->text + "'; add ': Type' or <...>"
                : "cannot infer field source type; add ': Type'");
  fieldRequests.clear();
}
} // namespace mettle
