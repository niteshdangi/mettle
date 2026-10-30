#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
std::optional<int> Checker::genericUnitVariant(Node &n) {
  auto spelling = n.text;
  auto delimiter = spelling.rfind("::");
  if (delimiter == std::string::npos)
    return std::nullopt;
  auto owner = typeName(spelling.substr(0, delimiter), n.span, current->owner);
  auto found = typeNames.find(owner);
  if (found == typeNames.end() || !checked.types->isSum(found->second))
    return std::nullopt;
  const Module::Product *declaration = nullptr;
  for (const auto &product : module.products)
    if (definitionName(product.span, product.name) == owner &&
        !productGenerics.at(&product).parameters.empty())
      declaration = &product;
  if (!declaration)
    return std::nullopt;
  auto variantName = spelling.substr(delimiter + 2);
  const auto &pattern = checked.types->product(found->second);
  int variant = -1;
  for (std::size_t i = 0; i < pattern.variants.size(); ++i)
    if (pattern.variants[i].name == variantName)
      variant = static_cast<int>(i);
  if (variant < 0 || !pattern.variants[variant].fields.empty())
    return std::nullopt;
  facts(n).variant = variant;
  auto origin = found->second;
  if (checked.types->product(origin).genericOrigin != Type::Unknown)
    origin = checked.types->product(origin).genericOrigin;
  const auto &environment = productGenerics.at(declaration);
  const auto &explicitArguments = n.ownerGenericArguments.empty()
                                      ? n.genericArguments
                                      : n.ownerGenericArguments;
  std::vector<Type> arguments(environment.parameters.size(), Type::Unknown);
  std::size_t index = 0;
  for (const auto &argument : explicitArguments) {
    if (!argument.region.empty())
      continue;
    if (index >= arguments.size()) {
      error("type", n.span, "excess generic constructor arguments");
      break;
    }
    if (inferredArgument(argument)) {
      ++index;
      continue;
    }
    arguments[index] = genericArgument(argument, environment.parameters[index]);
    ++index;
  }
  if (std::find(arguments.begin(), arguments.end(), Type::Unknown) ==
      arguments.end())
    return inference.fresh(
        checked.types->instantiateProduct(origin, std::move(arguments)));
  // Remaining arguments come from the expected type once it is known.
  auto result = inference.fresh();
  fieldRequests.push_back({&n, result, result, false, origin});
  return result;
}
std::optional<int> Checker::genericConstruction(Node &n, bool reachable,
                                                std::string_view name) {
  if (n.children.empty() || n.children[0]->kind != Kind::Name)
    return std::nullopt;
  auto spelling = n.children[0]->text;
  auto owner = std::string(name);
  std::string variantName;
  auto delimiter = spelling.rfind("::");
  if (delimiter != std::string::npos) {
    auto prefix = spelling.substr(0, delimiter);
    auto candidate = typeName(prefix, n.span, current->owner);
    if (auto found = typeNames.find(candidate);
        (found != typeNames.end() && checked.types->isSum(found->second)) ||
        aliases.contains(candidate)) {
      owner = candidate;
      variantName = spelling.substr(delimiter + 2);
    }
  }
  const Module::Product *declaration = nullptr;
  for (const auto *product : productsNamed(owner))
    if (!productGenerics.at(product).parameters.empty())
      declaration = product;
  GenericEnvironment *selected = nullptr;
  const std::vector<GenericParameter> *parameterSyntax = nullptr;
  Type patternType = Type::Unknown;
  if (declaration) {
    selected = &productGenerics.at(declaration);
    parameterSyntax = &declaration->genericParameters;
    patternType = typeNames.at(owner);
  } else if (auto alias = aliases.find(owner); alias != aliases.end()) {
    const auto &syntax = module.aliases[alias->second];
    auto &environment = aliasGenerics.at(&syntax);
    if (environment.parameters.empty())
      return std::nullopt;
    auto saved = genericEnvironment;
    genericEnvironment = &environment;
    patternType = annotation(syntax.target, syntax.span);
    genericEnvironment = saved;
    if (!checked.types->isProduct(patternType))
      return std::nullopt;
    selected = &environment;
    parameterSyntax = &syntax.genericParameters;
  } else
    return std::nullopt;
  auto origin = patternType;
  if (checked.types->product(origin).genericOrigin != Type::Unknown)
    origin = checked.types->product(origin).genericOrigin;
  auto constructorName = checked.types->product(origin).name + ".init";
  if (declaration && variantName.empty() && names.contains(constructorName)) {
    auto index = names.at(constructorName);
    return genericCall(n, reachable, index, 0);
  }
  auto &environment = *selected;
  const auto pattern = checked.types->product(patternType);
  auto enumeration = checked.types->isSum(patternType);
  if (!enumeration && !variantName.empty())
    return std::nullopt;
  std::vector<std::uint32_t> fields;
  if (enumeration) {
    int variant = -1;
    for (std::size_t i = 0; i < pattern.variants.size(); ++i)
      if (pattern.variants[i].name == variantName)
        variant = static_cast<int>(i);
    if (variant < 0) {
      error("name", n.span, "generic enum requires a named variant");
      return inference.fresh();
    }
    facts(n).variant = variant;
    fields = pattern.variants[variant].fields;
  } else {
    facts(n).constructor = true;
    for (std::size_t i = 0; i < pattern.fields.size(); ++i)
      fields.push_back(static_cast<std::uint32_t>(i));
  }
  if (pattern.layout.unionType) {
    if (n.children.size() != 2 || n.children[1]->name.empty()) {
      error("type", n.span,
            "union construction requires exactly one named field");
      return inference.fresh();
    }
    auto selected = std::find_if(fields.begin(), fields.end(), [&](auto field) {
      return pattern.fields[field].name == n.children[1]->name;
    });
    if (selected == fields.end()) {
      error("name", n.span, "unknown union constructor field");
      return inference.fresh();
    }
    facts(n).field = *selected;
    fields = {*selected};
  }
  std::vector<TypeBinding> bindings;
  for (auto parameter : environment.parameters)
    bindings.push_back({parameter, Type::Unknown});
  const auto &explicitArguments = n.children[0]->ownerGenericArguments.empty()
                                      ? n.children[0]->genericArguments
                                      : n.children[0]->ownerGenericArguments;
  std::vector<const GenericParameter *> parameters;
  for (const auto &parameter : *parameterSyntax)
    if (parameter.kind != GenericParameterKind::Region)
      parameters.push_back(&parameter);
  std::size_t genericIndex = 0;
  for (const auto &argument : explicitArguments) {
    if (!argument.region.empty())
      continue;
    if (genericIndex >= bindings.size()) {
      error("type", n.span, "excess generic constructor arguments");
      break;
    }
    if (!inferredArgument(argument))
      bindings[genericIndex].argument =
          genericArgument(argument, bindings[genericIndex].parameter);
    ++genericIndex;
  }
  if (!declaration && !enumeration && names.contains(constructorName)) {
    auto constructor = names.at(constructorName);
    auto &function = module.functions[constructor];
    auto caller = genericEnvironment;
    std::vector<TypeBinding> ownerPattern;
    const auto &source = checked.types->product(origin);
    for (std::size_t i = 0; i < source.genericParameters.size(); ++i)
      ownerPattern.push_back(
          {source.genericParameters[i], pattern.genericArguments[i]});
    genericEnvironment = &functionGenerics.at(&function);
    std::vector<Type> signature;
    for (const auto &parameter : function.parameters)
      signature.push_back(checked.types->substitute(
          annotation(parameter.annotation, parameter.span, function.owner),
          ownerPattern));
    genericEnvironment = caller;
    auto originalReachable = reachable;
    for (std::size_t i = 1; i < n.children.size(); ++i) {
      auto &argument = *n.children[i];
      auto variable = node(argument, reachable);
      this->fields(false);
      reachable &= facts(argument).flow.normal;
      auto target = i - 1;
      if (!argument.name.empty()) {
        target = signature.size();
        for (std::size_t p = 0; p < function.parameters.size(); ++p)
          if (function.parameters[p].name == argument.name)
            target = p;
      }
      if (target >= signature.size())
        continue;
      auto actual = inference.value(variable);
      const auto &parameter = function.parameters[target];
      auto borrowed =
          parameter.mode == "read" || parameter.mode == "mut" ||
          (parameter.mode.empty() && !checked.types->isCopy(signature[target]));
      if (borrowed && checked.types->isView(actual) &&
          !checked.types->isView(signature[target]))
        actual = checked.types->view(actual).payload;
      inferGeneric(signature[target], actual, bindings, argument.span);
    }
    completeGenericBindings(environment, bindings, n.span);
    genericObligations(environment, bindings, n.span);
    for (auto &binding : ownerPattern)
      binding.argument =
          normalizeGenericType(binding.argument, bindings, n.span);
    for (const auto &binding : bindings)
      if (binding.argument == Type::Unknown)
        error("type", n.span,
              "cannot infer generic alias constructor arguments");
    facts(n).constructor = false;
    return genericCall(n, originalReachable, constructor, 0, ownerPattern,
                       true);
  }
  std::vector<std::pair<Node *, int>> actuals;
  std::vector<bool> used(fields.size());
  bool named = false;
  for (std::size_t i = 1; i < n.children.size(); ++i) {
    auto &argument = *n.children[i];
    if (argument.kind == Kind::Closure && argument.name.empty() &&
        i - 1 < fields.size()) {
      // Explicit or already inferred arguments give a closure its signature.
      std::vector<TypeBinding> solved;
      for (const auto &binding : bindings)
        if (binding.argument != Type::Unknown)
          solved.push_back(binding);
      auto expected =
          checked.types->substitute(pattern.fields[fields[i - 1]].type, solved);
      if (checked.types->isFunctionPointer(expected))
        contextualize(argument, expected);
    }
    auto variable = node(argument, reachable);
    this->fields(false);
    reachable &= facts(argument).flow.normal;
    std::size_t target = i - 1;
    if (!argument.name.empty()) {
      named = true;
      target = fields.size();
      for (std::size_t j = 0; j < fields.size(); ++j)
        if (pattern.fields[fields[j]].name == argument.name)
          target = j;
    } else if (named)
      error("type", argument.span,
            "positional arguments must precede named arguments");
    facts(n).argumentOrder.push_back(target < fields.size() ? target : 0);
    actuals.push_back({&argument, variable});
    if (target >= fields.size()) {
      error("type", argument.span, "unknown or excess constructor argument");
      continue;
    }
    if (used[target])
      error("type", argument.span, "duplicate constructor argument");
    used[target] = true;
    if (!enumeration)
      visibleField(origin, fields[target], argument.span);
    inferGeneric(pattern.fields[fields[target]].type, inference.value(variable),
                 bindings, argument.span);
  }
  if (std::find(used.begin(), used.end(), false) != used.end())
    error("type", n.span, "missing constructor argument");
  if (auto hint = expectedTypes.find(&n);
      hint != expectedTypes.end() &&
      std::any_of(bindings.begin(), bindings.end(), [](const auto &binding) {
        return binding.argument == Type::Unknown;
      })) {
    auto expected = hint->second;
    if (checked.types->isProduct(expected)) {
      const auto &actual = checked.types->product(expected);
      if (actual.genericOrigin == origin &&
          actual.genericArguments.size() == bindings.size())
        for (std::size_t i = 0; i < bindings.size(); ++i)
          if (bindings[i].argument == Type::Unknown)
            bindings[i].argument = actual.genericArguments[i];
    }
  }
  auto caller = genericEnvironment;
  genericEnvironment = &environment;
  completeGenericBindings(environment, bindings, n.span);
  for (std::size_t i = 0; i < bindings.size(); ++i) {
    if (bindings[i].argument == Type::Unknown) {
      const auto &parameter = *parameters[i];
      if (!parameter.defaultType.empty())
        bindings[i].argument = checked.types->substitute(
            annotation(parameter.defaultType, parameter.span), bindings);
      else if (parameter.defaultValue)
        bindings[i].argument = checked.types->substitute(
            constantType(
                *parameter.defaultValue,
                checked.types->parameter(bindings[i].parameter).valueType),
            bindings);
    }
    if (bindings[i].argument == Type::Unknown)
      error("type", n.span,
            "cannot infer generic constructor argument '" +
                std::string(checked.types->name(bindings[i].parameter)) + "'");
  }
  genericEnvironment = caller;
  genericObligations(environment, bindings, n.span);
  std::vector<Type> arguments;
  for (const auto &binding : bindings)
    arguments.push_back(binding.argument);
  auto result =
      declaration
          ? checked.types->instantiateProduct(origin, std::move(arguments))
          : normalizeGenericType(patternType, bindings, n.span);
  for (std::size_t i = 0; i < actuals.size(); ++i) {
    auto target = facts(n).argumentOrder[i];
    if (target < fields.size())
      coerce(*actuals[i].first, actuals[i].second,
             inference.fresh(normalizeGenericType(
                 checked.types->product(result).fields[fields[target]].type, {},
                 actuals[i].first->span)),
             actuals[i].first->span);
  }
  return inference.fresh(result);
}
} // namespace mettle
