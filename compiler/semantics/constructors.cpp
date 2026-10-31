#include "semantics/checker.h"
#include "support/path.h"
#include <algorithm>
#include <functional>
#include <set>
#include <unordered_map>
#include <utility>

namespace mettle {
bool Checker::constructorShapeMatches(const Function &function,
                                      const Node &call) {
  std::vector<bool> used(function.parameters.size());
  std::unordered_map<std::string, std::size_t> labels;
  for (std::size_t i = 0; i < function.parameters.size(); ++i)
    if (!function.parameters[i].name.empty())
      labels.emplace(function.parameters[i].name, i);
  bool named = false;
  for (std::size_t i = 1; i < call.children.size(); ++i) {
    const auto &argument = *call.children[i];
    auto target = i - 1;
    if (!argument.name.empty()) {
      named = true;
      auto found = labels.find(argument.name);
      target =
          found == labels.end() ? function.parameters.size() : found->second;
    } else if (named)
      return false;
    if (target >= used.size() || used[target])
      return false;
    used[target] = true;
  }
  for (std::size_t i = 0; i < used.size(); ++i)
    if (!used[i] && !function.parameters[i].defaultValue.get())
      return false;
  return true;
}

bool Checker::constructorShapesOverlap(const Function &a, const Function &b) {
  const auto maximum = std::min(a.parameters.size(), b.parameters.size());
  std::vector<int> excluded(maximum + 2);
  auto restrict = [&](const Function &first, const Function &second) {
    std::unordered_map<std::string, std::size_t> labels;
    for (std::size_t i = 0; i < second.parameters.size(); ++i)
      if (!second.parameters[i].name.empty())
        labels.emplace(second.parameters[i].name, i);
    for (std::size_t i = 0; i < first.parameters.size(); ++i) {
      const auto &parameter = first.parameters[i];
      if (parameter.defaultValue.get())
        continue;
      auto found = labels.find(parameter.name);
      std::size_t begin = 0;
      if (!parameter.name.empty() && found != labels.end())
        begin = found->second + 1;
      auto end = std::min(i, maximum);
      if (begin <= end) {
        ++excluded[begin];
        --excluded[end + 1];
      }
    }
  };
  restrict(a, b);
  restrict(b, a);
  int active = 0;
  for (std::size_t count = 0; count <= maximum; ++count) {
    active += excluded[count];
    if (!active)
      return true;
  }
  return false;
}

void Checker::registerConstructors() {
  auto *savedCurrent = current;
  auto *savedEnvironment = genericEnvironment;
  for (std::size_t i = 0; i < module.functions.size(); ++i) {
    auto &function = module.functions[i];
    if (!function.constructor)
      continue;
    current = &function;
    genericEnvironment = &functionGenerics.at(&function);
    auto target = inference.value(functionVariables.at(&function));
    if (!checked.types->isProduct(target) ||
        checked.types->product(target).kind != AggregateKind::Product ||
        checked.types->product(target).layout.unionType) {
      error("type", function.span,
            "a constructor requires a nominal product target");
      continue;
    }
    auto origin = checked.types->product(target).genericOrigin;
    if (origin == Type::Unknown)
      origin = target;
    interfaces::Implementation applicability;
    applicability.target = target;
    applicability.parameters = genericEnvironment->parameters;
    applicability.equalities = genericEnvironment->equalities;
    applicability.requirements = interfaceAssumptions();
    applicability.span = function.span;
    const auto &regions = functionRegions(function);
    applicability.regions = regions.parameters;
    applicability.regionRequirements = regions.environment.assumptions;
    constructors[origin].push_back({i, std::move(applicability)});
  }
  genericEnvironment = savedEnvironment;
  current = savedCurrent;

  for (const auto &product : module.products) {
    auto origin = typeNames.find(definitionName(product.span, product.name));
    if (origin == typeNames.end() || !constructors.contains(origin->second))
      continue;
    for (const auto &[name, span] : product.deriveRequests)
      if (name != "Copy")
        error("feature", span,
              "derive(" + name +
                  ") is not implemented for types with an init constructor");
  }

  for (auto &[origin, candidates] : constructors) {
    std::sort(candidates.begin(), candidates.end(),
              [&](const auto &a, const auto &b) {
                auto left = module.functions[a.function].span;
                auto right = module.functions[b.function].span;
                return left.source == right.source ? left.begin < right.begin
                                                   : left.source < right.source;
              });
    for (std::size_t i = 0; i < candidates.size(); ++i)
      for (std::size_t j = 0; j < i; ++j) {
        const auto &later = candidates[i];
        const auto &earlier = candidates[j];
        if (!constructorShapesOverlap(module.functions[later.function],
                                      module.functions[earlier.function]))
          continue;
        interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                  diagnostics);
        auto bindings = solver.match(later.applicability.target,
                                     earlier.applicability.target, true);
        if (!bindings)
          continue;
        auto intersection = later.applicability;
        intersection.parameters.insert(intersection.parameters.end(),
                                       earlier.applicability.parameters.begin(),
                                       earlier.applicability.parameters.end());
        intersection.equalities.insert(intersection.equalities.end(),
                                       earlier.applicability.equalities.begin(),
                                       earlier.applicability.equalities.end());
        intersection.requirements.insert(
            intersection.requirements.end(),
            earlier.applicability.requirements.begin(),
            earlier.applicability.requirements.end());
        if (solver.constraints(intersection, *bindings,
                               module.functions[later.function].span, {}, true))
          error("type", module.functions[later.function].span,
                "overlapping constructor argument shapes for '" +
                    displayType(*checked.types, origin) + "'");
      }
  }
}

std::optional<std::vector<TypeBinding>> Checker::constructorApplicability(
    const ConstructorCandidate &candidate, Type type, Span span,
    interfaces::Solver &solver, std::span<const TypeBinding> seed) {
  auto applicability = candidate.applicability;
  std::vector<TypeBinding> known;
  for (const auto &binding : seed)
    if (binding.argument != Type::Unknown)
      known.push_back(binding);
  interfaces::Implementation boundParameters;
  for (const auto &binding : known)
    boundParameters.parameters.push_back(binding.parameter);
  auto checkedBindings = known;
  if (!solver.constraints(boundParameters, checkedBindings, span, {}, false))
    return std::nullopt;
  applicability.target = checked.types->substitute(applicability.target, known);
  for (auto &requirement : applicability.requirements) {
    requirement.subject = checked.types->substitute(requirement.subject, known);
    requirement.interfaceType =
        checked.types->substitute(requirement.interfaceType, known);
  }
  for (auto &equality : applicability.equalities) {
    equality.parameter = checked.types->substitute(equality.parameter, known);
    equality.argument = checked.types->substitute(equality.argument, known);
  }
  std::erase_if(applicability.parameters, [&](Type parameter) {
    return std::any_of(known.begin(), known.end(), [&](const auto &binding) {
      return binding.parameter == parameter;
    });
  });
  auto actualParameters = checked.types->typeParameters(type);
  std::vector<Type> identities;
  for (auto parameter : checked.types->typeParameters(applicability.target))
    if (std::find(actualParameters.begin(), actualParameters.end(),
                  parameter) != actualParameters.end())
      identities.push_back(parameter);
  for (auto parameter : identities)
    if (std::find(applicability.parameters.begin(),
                  applicability.parameters.end(),
                  parameter) == applicability.parameters.end())
      applicability.parameters.push_back(parameter);
  auto bindings = solver.applicable(applicability, type, span);
  if (bindings) {
    for (const auto &binding : *bindings)
      if (binding.parameter != binding.argument &&
          std::find(identities.begin(), identities.end(), binding.parameter) !=
              identities.end())
        return std::nullopt;
    bindings->insert(bindings->end(), known.begin(), known.end());
  }
  return bindings;
}

int Checker::genericCustomConstruction(Node &call, bool reachable, Type origin,
                                       Type patternType,
                                       GenericEnvironment &environment,
                                       bool alias) {
  std::vector<TypeBinding> explicitBindings;
  for (auto parameter : environment.parameters)
    explicitBindings.push_back({parameter, Type::Unknown});
  const auto &arguments = call.children[0]->ownerGenericArguments.empty()
                              ? call.children[0]->genericArguments
                              : call.children[0]->ownerGenericArguments;
  std::size_t next = 0;
  for (const auto &argument : arguments) {
    if (!argument.region.empty())
      continue;
    if (next >= explicitBindings.size()) {
      error("type", call.span, "excess generic constructor arguments");
      return inference.fresh();
    }
    if (!inferredArgument(argument))
      explicitBindings[next].argument =
          genericArgument(argument, explicitBindings[next].parameter);
    ++next;
  }
  auto *caller = genericEnvironment;
  std::optional<std::size_t> selected;
  std::vector<TypeBinding> selectedBindings;
  std::vector<TypeBinding> selectedOwner;
  bool missingType = false;
  bool shapeFound = false;
  const auto shapeCount =
      std::count_if(constructors.at(origin).begin(),
                    constructors.at(origin).end(), [&](const auto &candidate) {
                      return constructorShapeMatches(
                          module.functions[candidate.function], call);
                    });
  const auto ownerPattern =
      alias ? checked.types->product(patternType).genericArguments
            : checked.types->product(origin).genericParameters;
  std::vector<TypeBinding> knownOwner;
  for (const auto &binding : explicitBindings)
    if (binding.argument != Type::Unknown)
      knownOwner.push_back(binding);
  std::vector<Type> requestedArguments;
  for (auto argument : ownerPattern)
    requestedArguments.push_back(
        checked.types->substitute(argument, knownOwner));
  for (const auto &candidate : constructors.at(origin)) {
    auto &function = module.functions[candidate.function];
    if (!constructorShapeMatches(function, call))
      continue;
    shapeFound = true;
    auto &functionEnvironment = functionGenerics.at(&function);
    std::vector<TypeBinding> trial;
    for (auto parameter : functionEnvironment.parameters)
      trial.push_back({parameter, Type::Unknown});
    auto substituteTrial = [&](Type type) {
      std::vector<TypeBinding> known;
      for (const auto &binding : trial)
        if (binding.argument != Type::Unknown)
          known.push_back(binding);
      return checked.types->substitute(type, known);
    };
    const auto targetArguments =
        checked.types->product(candidate.applicability.target).genericArguments;
    if (targetArguments.size() != requestedArguments.size())
      continue;
    interfaces::Solver solver(*checked.types, *checked.interfaceData,
                              diagnostics, interfaceAssumptions(),
                              regionEnvironment());
    if (caller)
      solver.setEqualities(caller->equalities);
    auto incorporate = [&](const std::vector<TypeBinding> &newBindings) {
      for (const auto &binding : newBindings)
        for (auto &entry : trial)
          if (entry.parameter == binding.parameter) {
            if (entry.argument != Type::Unknown &&
                entry.argument != binding.argument)
              return false;
            entry.argument = binding.argument;
          }
      return true;
    };
    bool compatible = true;
    for (std::size_t i = 0; i < requestedArguments.size(); ++i) {
      auto parameters = checked.types->typeParameters(requestedArguments[i]);
      if (std::any_of(parameters.begin(), parameters.end(), [&](Type value) {
            return std::any_of(explicitBindings.begin(), explicitBindings.end(),
                               [&](const auto &binding) {
                                 return binding.parameter == value &&
                                        binding.argument == Type::Unknown;
                               });
          }))
        continue;
      auto pattern = substituteTrial(targetArguments[i]);
      auto actual = solver.normalize(requestedArguments[i], {}, call.span);
      auto matched = solver.match(pattern, actual);
      if (!matched || !incorporate(*matched)) {
        compatible = false;
        break;
      }
    }
    if (!compatible)
      continue;

    genericEnvironment = &functionEnvironment;
    annotationRegionScopes.push_back(functionRegions(function));
    std::vector<Type> signature;
    for (const auto &parameter : function.parameters)
      signature.push_back(
          annotation(parameter.annotation, parameter.span, function.owner));
    annotationRegionScopes.pop_back();
    genericEnvironment = caller;
    std::set<Type> needed;
    for (std::size_t i = 0; i < requestedArguments.size(); ++i) {
      const auto parameters =
          checked.types->typeParameters(requestedArguments[i]);
      if (std::any_of(parameters.begin(), parameters.end(), [&](Type value) {
            return std::any_of(explicitBindings.begin(), explicitBindings.end(),
                               [&](const auto &binding) {
                                 return binding.parameter == value &&
                                        binding.argument == Type::Unknown;
                               });
          }))
        for (auto parameter : checked.types->typeParameters(targetArguments[i]))
          needed.insert(parameter);
    }
    for (const auto &binding : trial)
      if (binding.argument == Type::Unknown &&
          std::find(targetArguments.begin(), targetArguments.end(),
                    binding.parameter) == targetArguments.end())
        needed.insert(binding.parameter);
    bool inspectArguments = false;
    for (auto type : signature)
      for (auto parameter : checked.types->typeParameters(type))
        inspectArguments |= needed.contains(parameter);
    std::set<Type> inferred;
    if (inspectArguments) {
      std::function<std::optional<std::vector<TypeBinding>>(Type, Type)> match;
      match = [&](Type pattern,
                  Type actual) -> std::optional<std::vector<TypeBinding>> {
        if (auto direct = solver.match(pattern, actual))
          return direct;
        if ((checked.types->isView(pattern) && checked.types->isView(actual)) ||
            (checked.types->isPointer(pattern) &&
             checked.types->isPointer(actual))) {
          const auto left = checked.types->view(pattern);
          const auto right = checked.types->view(actual);
          if (left.mode == right.mode)
            return match(left.payload, right.payload);
          return std::nullopt;
        }
        if (checked.types->isSlice(pattern) &&
            checked.types->isProduct(actual)) {
          const auto array = checked.types->product(actual);
          if (array.kind == AggregateKind::Array &&
              array.components.size() == 1)
            return match(checked.types->slice(pattern).element,
                         array.components.front());
        }
        std::vector<TypeBinding> bindings;
        auto part = [&](Type left, Type right) {
          auto found = match(checked.types->substitute(left, bindings), right);
          if (!found)
            return false;
          bindings.insert(bindings.end(), found->begin(), found->end());
          return true;
        };
        if (checked.types->isFunctionPointer(pattern) &&
            checked.types->isCallable(actual)) {
          const auto expected = checked.types->callable(pattern);
          const auto found = checked.types->callable(actual);
          if (expected.parameters.size() != found.parameters.size())
            return std::nullopt;
          for (std::size_t p = 0; p < expected.parameters.size(); ++p)
            if (!part(expected.parameters[p].type, found.parameters[p].type))
              return std::nullopt;
          if (!part(expected.result, found.result) ||
              (expected.error != Type::Unknown &&
               found.error != Type::Unknown &&
               !part(expected.error, found.error)))
            return std::nullopt;
          return bindings;
        }
        if (!checked.types->isProduct(pattern) ||
            !checked.types->isProduct(actual))
          return std::nullopt;
        const auto left = checked.types->product(pattern);
        const auto right = checked.types->product(actual);
        if (left.kind != right.kind ||
            left.genericOrigin != right.genericOrigin ||
            left.kind == AggregateKind::NativeVector)
          return std::nullopt;
        if (left.genericOrigin == Type::Unknown &&
            (left.kind == AggregateKind::Product ||
             left.kind == AggregateKind::Enumeration ||
             left.kind == AggregateKind::Opaque))
          return std::nullopt;
        const auto &a = left.genericOrigin != Type::Unknown
                            ? left.genericArguments
                            : left.components;
        const auto &b = right.genericOrigin != Type::Unknown
                            ? right.genericArguments
                            : right.components;
        if (a.size() != b.size())
          return std::nullopt;
        for (std::size_t p = 0; p < a.size(); ++p)
          if (!part(a[p], b[p]))
            return std::nullopt;
        if (left.kind == AggregateKind::Array) {
          if (left.arrayCount == Type::Unknown) {
            if (right.arrayCount != Type::Unknown ||
                left.fields.size() != right.fields.size())
              return std::nullopt;
          } else {
            auto count =
                right.arrayCount != Type::Unknown
                    ? right.arrayCount
                    : checked.types->constant(
                          checked.types->parameter(left.arrayCount).valueType,
                          right.fields.size());
            if (!part(left.arrayCount, count))
              return std::nullopt;
          }
        }
        return bindings;
      };
      std::unordered_map<std::string, std::size_t> labels;
      for (std::size_t i = 0; i < function.parameters.size(); ++i)
        labels.emplace(function.parameters[i].name, i);
      bool argumentReachable = reachable;
      for (std::size_t i = 1; i < call.children.size(); ++i) {
        auto &argument = *call.children[i];
        std::size_t target = i - 1;
        if (!argument.name.empty())
          target = labels.at(argument.name);
        if (target >= signature.size())
          continue;
        auto known = nodeVariables.find(&argument);
        if (known == nodeVariables.end()) {
          auto expected = substituteTrial(signature[target]);
          Type closureContract = Type::Unknown;
          if (argument.kind == Kind::Closure) {
            if (checked.types->isFunctionPointer(expected))
              closureContract = expected;
            else if (checked.types->isParameter(expected))
              closureContract = substituteTrial(
                  checked.types->parameter(expected).callableConstraint);
          }
          if (closureContract != Type::Unknown) {
            std::vector<TypeBinding> open;
            for (const auto &binding : trial)
              if (binding.argument == Type::Unknown)
                open.push_back(binding);
            contextualize(argument,
                          checked.types->substitute(closureContract, open));
          } else if (expected != Type::Unknown &&
                     !checked.types->isSymbolic(expected))
            contextualize(argument, expected);
          node(argument, argumentReachable);
          known = nodeVariables.find(&argument);
        }
        fields(false);
        argumentReachable &= facts(argument).flow.normal;
        auto actual = inference.value(known->second);
        auto pattern = substituteTrial(signature[target]);
        const auto &parameter = function.parameters[target];
        bool borrowed = parameter.mode == "read" || parameter.mode == "mut" ||
                        (parameter.mode.empty() &&
                         !checked.types->isCopy(signature[target]));
        if (borrowed && checked.types->isView(actual) &&
            !checked.types->isView(pattern))
          actual = checked.types->view(actual).payload;
        if (actual == Type::Unknown)
          continue;
        auto matched = match(pattern, actual);
        if (matched) {
          if (pattern == actual)
            for (auto parameter : checked.types->typeParameters(pattern))
              if (needed.contains(parameter))
                for (auto &entry : trial)
                  if (entry.parameter == parameter &&
                      entry.argument == Type::Unknown) {
                    entry.argument = parameter;
                    inferred.insert(parameter);
                  }
          for (const auto &binding : *matched)
            if (needed.contains(binding.parameter))
              inferred.insert(binding.parameter);
          incorporate(*matched);
        }
      }
      for (std::size_t round = 0; round < trial.size(); ++round) {
        bool progress = false;
        for (const auto &binding : std::vector<TypeBinding>(trial)) {
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
          auto inferPart = [&](Type pattern, Type value) {
            auto found = match(substituteTrial(pattern), value);
            if (!found)
              return;
            auto before = trial;
            if (!incorporate(*found))
              return;
            for (const auto &item : *found)
              if (needed.contains(item.parameter))
                inferred.insert(item.parameter);
            for (std::size_t i = 0; i < trial.size(); ++i)
              progress |= before[i].argument != trial[i].argument;
          };
          for (std::size_t i = 0; i < expected.parameters.size(); ++i)
            inferPart(expected.parameters[i].type, actual.parameters[i].type);
          inferPart(expected.result, actual.result);
          if (expected.error != Type::Unknown && actual.error != Type::Unknown)
            inferPart(expected.error, actual.error);
        }
        if (!progress)
          break;
      }
    }
    auto owner = explicitBindings;
    for (std::size_t i = 0; i < requestedArguments.size(); ++i) {
      const auto parameters = checked.types->typeParameters(targetArguments[i]);
      if (std::none_of(
              parameters.begin(), parameters.end(),
              [&](Type parameter) { return inferred.contains(parameter); }))
        continue;
      auto inferredType = substituteTrial(targetArguments[i]);
      auto remaining = checked.types->typeParameters(inferredType);
      if (std::any_of(remaining.begin(), remaining.end(), [&](Type parameter) {
            return std::any_of(trial.begin(), trial.end(),
                               [&](const auto &binding) {
                                 return binding.parameter == parameter &&
                                        binding.argument == Type::Unknown;
                               });
          }))
        continue;
      auto matched = solver.match(requestedArguments[i], inferredType);
      if (!matched)
        continue;
      if (requestedArguments[i] == inferredType)
        for (auto &entry : owner)
          if (entry.parameter == inferredType &&
              entry.argument == Type::Unknown)
            entry.argument = inferredType;
      for (const auto &binding : *matched)
        for (auto &entry : owner)
          if (entry.parameter == binding.parameter &&
              entry.argument == Type::Unknown)
            entry.argument = binding.argument;
    }
    if (shapeCount == 1 && function.implementation < 0)
      if (auto hint = expectedTypes.find(&call); hint != expectedTypes.end())
        if (auto matched = solver.match(patternType, hint->second))
          for (const auto &binding : *matched)
            for (auto &entry : owner)
              if (entry.parameter == binding.parameter &&
                  entry.argument == Type::Unknown)
                entry.argument = binding.argument;
    for (auto &binding : owner)
      if (binding.argument == Type::Unknown)
        if (auto value = environment.defaults.find(binding.parameter);
            value != environment.defaults.end())
          binding.argument = checked.types->substitute(value->second, owner);
    for (auto &binding : trial)
      if (binding.argument == Type::Unknown)
        if (auto value = functionEnvironment.defaults.find(binding.parameter);
            value != functionEnvironment.defaults.end())
          binding.argument = substituteTrial(value->second);
    if (std::any_of(owner.begin(), owner.end(), [](const auto &binding) {
          return binding.argument == Type::Unknown;
        })) {
      missingType = true;
      continue;
    }
    std::vector<Type> ownerArguments;
    for (const auto &binding : owner)
      ownerArguments.push_back(binding.argument);
    auto type = alias ? checked.types->substitute(patternType, owner)
                : ownerArguments.empty()
                    ? origin
                    : checked.types->instantiateProduct(origin, ownerArguments);
    type = solver.normalize(type, {}, call.span);
    auto applicable =
        constructorApplicability(candidate, type, call.span, solver, trial);
    if (!applicable)
      continue;
    if (selected) {
      error("type", call.span, "ambiguous constructor applicability");
      return inference.fresh();
    }
    selected = candidate.function;
    selectedBindings = std::move(*applicable);
    selectedOwner = std::move(owner);
  }
  genericEnvironment = caller;
  if (!selected) {
    if (shapeFound && missingType)
      error("type", call.span, "cannot infer generic constructor arguments");
    else
      error("type", call.span,
            "no constructor of '" + displayPath(call.children[0]->text) +
                "' accepts this argument shape");
    return inference.fresh();
  }
  completeGenericBindings(environment, selectedOwner, call.span);
  genericObligations(environment, selectedOwner, call.span);
  auto &function = module.functions[*selected];
  formatArguments(call, function, 0);
  requireFeatures(facts(function).targetFeatures, call.span);
  if (function.unsafeFunction)
    requireUnsafe(call.span);
  return *genericCall(call, reachable, *selected, 0, selectedBindings, true);
}

void Checker::constructor(Function &function) {
  if (!function.constructor)
    return;
  if (scopes.back().contains("self")) {
    error("name", function.span,
          "a constructor parameter cannot shadow 'self'");
    return;
  }
  auto type = annotation(function.annotation, function.span, function.owner);
  facts(function).constructorSelfSlot =
      local("self", inference.fresh(type), true, function.span);
}
} // namespace mettle
