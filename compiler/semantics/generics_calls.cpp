#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
std::optional<int> Checker::genericCall(
    Node &n, bool reachable, std::size_t callee, std::size_t receiverOffset,
    std::span<const TypeBinding> ownerBindings, bool aliasConstructor) {
  auto &function = module.functions[callee];
  auto &environment = functionGenerics.at(&function);
  if (environment.parameters.empty() && !aliasConstructor &&
      functionRegions(function).parameters.empty())
    return std::nullopt;
  auto caller = genericEnvironment;
  facts(n).callee = static_cast<int>(callee);
  if (!checked.symbols->accessible(function.span,
                                   checked.symbols->moduleOf(n.span)))
    error("name", n.span, "generic function is inaccessible");
  if (function.destructor)
    error("ownership", n.span, "cannot invoke a destructor directly");
  if (receiverOffset && function.receiver == "static")
    error("type", n.span, "static function requires a type-qualified call");
  std::vector<TypeBinding> bindings;
  for (auto parameter : environment.parameters)
    bindings.push_back({parameter, Type::Unknown});
  seedInterfaceBindings(n, environment, bindings);
  for (std::size_t i = 0;
       i < facts(n).implementationArguments.size() && i < bindings.size(); ++i)
    bindings[i].argument = facts(n).implementationArguments[i];
  for (auto &binding : bindings)
    for (const auto &owner : ownerBindings)
      if (binding.parameter == owner.parameter)
        binding.argument = owner.argument;
  if (ownerBindings.empty() && !aliasConstructor)
    explicitGenericBindings(function, *n.children[0], environment, bindings,
                            n.span);
  genericEnvironment = &environment;
  annotationRegionScopes.push_back(functionRegions(function));
  std::vector<Type> signature;
  std::vector<ParameterMode> modes;
  for (const auto &parameter : function.parameters) {
    auto type =
        annotation(parameter.annotation, parameter.span, function.owner);
    signature.push_back(type);
    modes.push_back(parameter.mode == "take"      ? ParameterMode::Take
                    : parameter.mode == "read"    ? ParameterMode::Read
                    : parameter.mode == "mut"     ? ParameterMode::Mut
                    : checked.types->isCopy(type) ? ParameterMode::Value
                                                  : ParameterMode::Read);
  }
  auto resultPattern = inference.value(functionVariables.at(&function));
  auto errorPattern =
      function.error.empty()
          ? Type::Unknown
          : annotation(function.error, function.span, function.owner);
  annotationRegionScopes.pop_back();
  genericEnvironment = caller;
  std::vector<bool> used(signature.size());
  if (receiverOffset && !signature.empty()) {
    auto &receiver = *n.children[0]->children[0];
    if (function.receiver == "mut")
      requireMutablePlace(receiver);
    auto actual = facts(n).receiverPlan
                      ? facts(n).receiverPlan->target
                      : inference.value(nodeVariables.at(&receiver));
    if (!facts(n).receiverPlan) {
      while (checked.types->isView(actual))
        actual = checked.types->view(actual).payload;
      if (facts(n).optional && checked.types->isSum(actual))
        actual = checked.types->product(actual).components[0];
    }
    inferGeneric(signature[0], actual, bindings, receiver.span);
    used[0] = true;
  }
  std::vector<std::pair<Node *, int>> actuals;
  bool named = false, misbound = false;
  for (std::size_t i = 1; i < n.children.size(); ++i) {
    auto &argument = *n.children[i];
    auto known = nodeVariables.find(&argument);
    if (known == nodeVariables.end() && argument.name.empty() &&
        i - 1 + receiverOffset < signature.size()) {
      std::vector<TypeBinding> solved, open;
      for (const auto &binding : bindings)
        (binding.argument == Type::Unknown ? open : solved).push_back(binding);
      auto expected =
          checked.types->substitute(signature[i - 1 + receiverOffset], solved);
      if (checked.types->isParameter(expected) &&
          checked.types->parameter(expected).callableConstraint !=
              Type::Unknown) {
        // Parameters still being inferred stay open in the closure's context.
        auto contract = checked.types->substitute(
            checked.types->parameter(expected).callableConstraint, solved);
        if (argument.kind == Kind::Closure)
          contextualize(argument, checked.types->substitute(contract, open));
      } else if (argument.kind == Kind::Closure &&
                 checked.types->isFunctionPointer(expected))
        contextualize(argument, checked.types->substitute(expected, open));
      else if (expected != Type::Unknown &&
               !checked.types->isSymbolic(expected))
        contextualize(argument, expected);
    }
    auto variable = known == nodeVariables.end() ? node(argument, reachable)
                                                 : known->second;
    fields(false);
    reachable &= facts(argument).flow.normal;
    std::size_t target = i - 1 + receiverOffset;
    bool misordered = false;
    if (!argument.name.empty()) {
      named = true;
      auto found =
          std::find_if(function.parameters.begin(), function.parameters.end(),
                       [&](const auto &parameter) {
                         return parameter.name == argument.name;
                       });
      target = static_cast<std::size_t>(found - function.parameters.begin());
    } else if (named) {
      misbound = misordered = true;
      error("type", argument.span,
            "positional arguments must precede named arguments");
    }
    if (target >= signature.size()) {
      misbound = true;
      error("type", argument.span, "unknown or excess generic-call argument");
      facts(n).argumentOrder.push_back(0);
      actuals.push_back({&argument, variable});
      continue;
    }
    if (used[target] && !misordered) {
      misbound = true;
      error("type", argument.span, "duplicate argument");
    }
    used[target] = true;
    facts(n).argumentOrder.push_back(target);
    if (modes[target] == ParameterMode::Mut)
      requireMutablePlace(argument);
    auto actual = inference.value(variable);
    if (modes[target] == ParameterMode::Read ||
        modes[target] == ParameterMode::Mut) {
      auto expected = checked.types->substitute(signature[target], bindings);
      if (expected != Type::Unknown && !checked.types->isSymbolic(expected) &&
          borrowCoercion(argument, variable, expected, modes[target]))
        actual = expected;
    }
    if ((modes[target] == ParameterMode::Read ||
         modes[target] == ParameterMode::Mut) &&
        checked.types->isView(actual) &&
        !checked.types->isView(signature[target]))
      actual = checked.types->view(actual).payload;
    inferGeneric(signature[target], actual, bindings, argument.span);
    actuals.push_back({&argument, variable});
  }
  for (std::size_t round = 0; round < bindings.size(); ++round) {
    bool progress = false;
    for (const auto &binding : std::vector<TypeBinding>(bindings)) {
      if (binding.argument == Type::Unknown ||
          !checked.types->isParameter(binding.parameter))
        continue;
      auto contract =
          checked.types->parameter(binding.parameter).callableConstraint;
      if (contract == Type::Unknown ||
          !checked.types->isCallable(binding.argument))
        continue;
      const auto expected = checked.types->callable(contract);
      const auto actual = checked.types->callable(binding.argument);
      if (expected.parameters.size() != actual.parameters.size())
        continue;
      auto before = bindings;
      for (std::size_t i = 0; i < actual.parameters.size(); ++i)
        inferGeneric(expected.parameters[i].type, actual.parameters[i].type,
                     bindings, n.span);
      inferGeneric(expected.result, actual.result, bindings, n.span);
      if (expected.error != Type::Unknown && actual.error != Type::Unknown)
        inferGeneric(expected.error, actual.error, bindings, n.span);
      for (std::size_t i = 0; i < bindings.size(); ++i)
        progress |= before[i].argument != bindings[i].argument;
    }
    if (!progress)
      break;
  }
  if (auto hint = expectedTypes.find(&n);
      hint != expectedTypes.end() &&
      std::any_of(bindings.begin(), bindings.end(), [](const auto &binding) {
        return binding.argument == Type::Unknown;
      })) {
    // The expected type only completes what the arguments left open.
    auto trial = bindings;
    auto expected = hint->second;
    if (facts(n).optional && checked.types->isProduct(expected) &&
        checked.types->product(expected).kind == AggregateKind::Optional)
      expected = checked.types->product(expected).components[0];
    inferFromExpected(resultPattern, expected, trial);
    for (std::size_t i = 0; i < bindings.size(); ++i)
      if (bindings[i].argument == Type::Unknown)
        bindings[i].argument = trial[i].argument;
  }
  genericEnvironment = &environment;
  completeGenericBindings(environment, bindings, n.span);
  for (std::size_t i = 0; i < bindings.size(); ++i) {
    if (bindings[i].argument == Type::Unknown)
      error("type", n.span,
            "cannot infer generic argument '" +
                std::string(checked.types->name(bindings[i].parameter)) +
                "'; supply explicit ::<...> arguments");
  }
  genericEnvironment = caller;
  std::vector<RegionBinding> explicitRegions;
  std::size_t regionIndex = 0;
  for (const auto &argument : n.children[0]->genericArguments)
    if (!argument.region.empty() &&
        regionIndex < functionRegions(function).parameters.size())
      explicitRegions.push_back(
          {functionRegions(function).parameters[regionIndex++],
           regionReference(argument.region, argument.span)});
  genericObligations(environment, bindings, n.span, explicitRegions);
  for (const auto &binding : bindings)
    facts(n).typeArguments.push_back(binding.argument);
  for (auto type : signature)
    facts(n).callParameterTypes.push_back(
        normalizeCallType(type, bindings, function, n.span));
  for (std::size_t i = 0; i < actuals.size(); ++i) {
    auto target = facts(n).argumentOrder[i];
    if (target >= signature.size())
      continue;
    auto [argument, variable] = actuals[i];
    auto expected = facts(n).callParameterTypes[target];
    auto actual = inference.value(variable);
    if ((modes[target] == ParameterMode::Read ||
         modes[target] == ParameterMode::Mut) &&
        borrowCoercion(*argument, variable, expected, modes[target]))
      continue;
    if ((modes[target] == ParameterMode::Read ||
         modes[target] == ParameterMode::Mut) &&
        checked.types->isView(actual) &&
        checked.types->view(actual).payload == expected)
      variable = inference.fresh(expected);
    coerce(*argument, variable, inference.fresh(expected), argument->span);
  }
  completeArguments(n, function, used, !misbound);
  facts(n).receiverReservation = receiverOffset && function.receiver == "mut";
  auto result = normalizeCallType(resultPattern, bindings, function, n.span);
  facts(n).effect = normalizeCallType(errorPattern, bindings, function, n.span);
  if (facts(n).effect != Type::Unknown && !effectContext)
    error("effects", n.span, "throwing generic call requires try or capture");
  facts(n).callResult =
      facts(n).effect == Type::Unknown
          ? result
          : checked.types->structural(AggregateKind::Outcome,
                                      {result, facts(n).effect});
  for (auto type : facts(function).defaultAbiResults)
    facts(n).callDefaultAbiResults.push_back(
        normalizeCallType(type, bindings, function, n.span));
  for (auto type : facts(function).defaultValueTypes)
    facts(n).callDefaultValueTypes.push_back(
        normalizeCallType(type, bindings, function, n.span));
  auto variable = inference.fresh(result);
  genericCallRequests.push_back(
      {&n, &function, variable, bindings, caller, current});
  if (facts(n).optional)
    return inference.composite(AggregateKind::Optional, {variable});
  return variable;
}
void Checker::inferFromExpected(Type pattern, Type expected,
                                std::vector<TypeBinding> &bindings) {
  if (expected == Type::Unknown)
    return;
  for (auto &binding : bindings)
    if (binding.parameter == pattern) {
      if (binding.argument == Type::Unknown)
        binding.argument = expected;
      return;
    }
  if ((checked.types->isView(pattern) && checked.types->isView(expected)) ||
      (checked.types->isPointer(pattern) &&
       checked.types->isPointer(expected))) {
    inferFromExpected(checked.types->view(pattern).payload,
                      checked.types->view(expected).payload, bindings);
    return;
  }
  if (!checked.types->isProduct(pattern) || !checked.types->isProduct(expected))
    return;
  const auto &left = checked.types->product(pattern);
  const auto &right = checked.types->product(expected);
  if (left.kind != right.kind || left.genericOrigin != right.genericOrigin)
    return;
  const auto &a = left.genericOrigin != Type::Unknown ? left.genericArguments
                                                      : left.components;
  const auto &b = right.genericOrigin != Type::Unknown ? right.genericArguments
                                                       : right.components;
  if (a.size() == b.size())
    for (std::size_t i = 0; i < a.size(); ++i)
      inferFromExpected(a[i], b[i], bindings);
}
void Checker::resolveGenericCalls() {
  for (auto &request : genericCallRequests) {
    auto declarationResult =
        inference.value(functionVariables.at(request.function));
    if (declarationResult == Type::Unknown ||
        declarationResult == request.resolvedDeclaration)
      continue;
    request.resolvedDeclaration = declarationResult;
    auto saved = genericEnvironment;
    auto *savedCaller = current;
    current = request.caller;
    genericEnvironment = request.environment;
    auto result = normalizeCallType(declarationResult, request.bindings,
                                    *request.function, request.node->span);
    inference.equal(request.result, inference.fresh(result),
                    request.node->span);
    auto &call = facts(*request.node);
    call.callResult = call.effect == Type::Unknown
                          ? result
                          : checked.types->structural(AggregateKind::Outcome,
                                                      {result, call.effect});
    call.callDefaultAbiResults.clear();
    call.callDefaultValueTypes.clear();
    for (auto type : facts(*request.function).defaultAbiResults)
      call.callDefaultAbiResults.push_back(normalizeCallType(
          type, request.bindings, *request.function, request.node->span));
    for (auto type : facts(*request.function).defaultValueTypes)
      call.callDefaultValueTypes.push_back(normalizeCallType(
          type, request.bindings, *request.function, request.node->span));
    genericEnvironment = saved;
    current = savedCaller;
  }
}
} // namespace mettle
