#include "semantics/interfaces.h"
#include "support/limits.h"
#include "support/path.h"
#include <algorithm>
#include <functional>
#include <stdexcept>

namespace mettle::interfaces {
namespace {
Type resolve(Type type, const std::vector<TypeBinding> &bindings,
             TypeStore &types) {
  for (unsigned depth = 0; depth < limits::typeDepth; ++depth) {
    auto next = types.substitute(type, bindings);
    if (next == type)
      return type;
    type = next;
  }
  throw std::length_error("implementation substitution depth limit exceeded");
}
std::vector<Type> identityParameters(Type type, const TypeStore &types) {
  std::vector<Type> result;
  std::set<Type> visited;
  std::function<void(Type)> visit = [&](Type current) {
    if (!visited.insert(current).second || types.isProjection(current))
      return;
    if (types.isParameter(current) ||
        (types.isConstant(current) &&
         types.parameter(current).kind == TypeParameterKind::Constant)) {
      result.push_back(current);
      return;
    }
    if (types.isView(current) || types.isPointer(current))
      visit(types.view(current).payload);
    else if (types.isSlice(current))
      visit(types.slice(current).element);
    else if (types.isProduct(current)) {
      const auto &product = types.product(current);
      for (auto argument : product.genericArguments)
        visit(argument);
      for (auto component : product.components)
        visit(component);
      if (product.arrayCount != Type::Unknown)
        visit(product.arrayCount);
    } else if (types.isErased(current))
      for (auto argument : types.erased(current).arguments)
        visit(argument);
    else if (types.isFunctionPointer(current)) {
      const auto &signature = types.callable(current);
      for (const auto &parameter : signature.parameters)
        visit(parameter.type);
      visit(signature.result);
      visit(signature.error);
    }
  };
  visit(type);
  return result;
}
bool determined(Type type, const Implementation &implementation,
                const std::set<Type> &known, const TypeStore &types) {
  for (auto parameter : types.typeParameters(type))
    if (std::find(implementation.parameters.begin(),
                  implementation.parameters.end(),
                  parameter) != implementation.parameters.end() &&
        !known.contains(parameter))
      return false;
  return true;
}
} // namespace

bool Solver::equalities(std::span<const TypeBinding> equations,
                        std::span<const Type> parameters,
                        std::vector<TypeBinding> &bindings, Span span,
                        bool potential) {
  std::vector<TypeBinding> solved;
  for (const auto &binding : bindings)
    if (binding.argument != Type::Unknown)
      solved.push_back(binding);
  std::map<Type, Type> projected;
  for (const auto &equation : equations) {
    if (++steps > limits::activeLoans) {
      regionInconclusive = true;
      if (!limitReported)
        diagnostics.error("limit", span,
                          "implementation constraint resource limit exceeded");
      limitReported = true;
      return false;
    }
    auto left = resolve(equation.parameter, solved, types);
    auto right = resolve(equation.argument, solved, types);
    if (!potential) {
      left = normalize(left, {}, span);
      right = normalize(right, {}, span);
    }
    if (left == right)
      continue;
    auto unified = match(left, right, true, &regionEnvironment);
    if (!unified) {
      auto unresolved = [&](Type type) {
        return types.isProjection(type) ||
               (types.isConstant(type) &&
                types.parameter(type).kind == TypeParameterKind::Expression);
      };
      if (!potential || (!unresolved(left) && !unresolved(right)))
        return false;
      if (!unresolved(left))
        std::swap(left, right);
      auto [known, inserted] = projected.emplace(left, right);
      if (!inserted && !match(known->second, right, true, &regionEnvironment))
        return false;
      continue;
    }
    for (auto binding : *unified) {
      if (binding.parameter == binding.argument)
        continue;
      auto owned = [&](Type parameter) {
        return std::find(parameters.begin(), parameters.end(), parameter) !=
               parameters.end();
      };
      // A bare parameter on the other side may stand for an implementation
      // parameter, so orient the binding towards the one being solved.
      if (!owned(binding.parameter) && owned(binding.argument) &&
          types.isParameter(binding.argument))
        std::swap(binding.parameter, binding.argument);
      if (!owned(binding.parameter))
        return false;
      solved.push_back(binding);
    }
  }
  for (auto &binding : solved)
    binding.argument = resolve(binding.argument, solved, types);
  for (auto &binding : bindings)
    if (auto found = std::find_if(solved.begin(), solved.end(),
                                  [&](const auto &value) {
                                    return value.parameter == binding.parameter;
                                  });
        found != solved.end())
      binding.argument = found->argument;
  for (const auto &binding : solved)
    if (std::none_of(bindings.begin(), bindings.end(), [&](const auto &value) {
          return value.parameter == binding.parameter;
        }))
      bindings.push_back(binding);
  return true;
}

bool Solver::constraints(const Implementation &implementation,
                         std::vector<TypeBinding> &bindings, Span span,
                         std::span<const RegionBinding> regions,
                         bool potential) {
  auto equations = implementation.equalities;
  for (auto &equation : equations) {
    equation.parameter = types.substituteRegions(equation.parameter, regions);
    equation.argument = types.substituteRegions(equation.argument, regions);
  }
  // Parameters that appear only in an associated-type binding or a callable
  // result are determined by the arguments they constrain.
  for (const auto &requirement : implementation.requirements) {
    if (requirement.property != Property::Interface ||
        !types.isErased(requirement.interfaceType) ||
        types.erased(requirement.interfaceType).associated.empty())
      continue;
    auto bare = types.erased(requirement.interfaceType);
    auto bound = std::move(bare.associated);
    bare.associated.clear();
    const auto &definition = database.definitions[bare.declaration];
    auto interfaceType = types.erasedType(std::move(bare));
    for (const auto &binding : bound) {
      auto item = std::find_if(
          definition.associated.begin(), definition.associated.end(),
          [&](const auto &associated) {
            return associated.parameter == binding.parameter;
          });
      if (item == definition.associated.end() || !item->parameters.empty())
        continue;
      equations.push_back(
          {types.projection(
               requirement.subject, interfaceType,
               static_cast<std::size_t>(item - definition.associated.begin())),
           types.substituteRegions(binding.argument, regions)});
    }
  }
  for (auto parameter : implementation.parameters) {
    if (!types.isParameter(parameter))
      continue;
    auto contract = types.parameter(parameter).callableConstraint;
    auto actual = resolve(parameter, bindings, types);
    if (contract == Type::Unknown || actual == parameter ||
        !types.isCallable(actual))
      continue;
    equations.push_back(
        {types.callable(contract).result, types.callable(actual).result});
  }
  if (!equalities(equations, implementation.parameters, bindings, span,
                  potential))
    return false;
  auto substituted = [&](Type type) {
    return types.substituteRegions(resolve(type, bindings, types), regions);
  };
  for (auto parameter : implementation.parameters) {
    auto actual = substituted(parameter);
    auto bound = std::find_if(
        bindings.begin(), bindings.end(),
        [&](const auto &binding) { return binding.parameter == parameter; });
    if (!potential && bound == bindings.end())
      return false;
    if (types.isConstant(parameter)) {
      if (!types.isConstant(actual) || types.parameter(parameter).valueType !=
                                           types.parameter(actual).valueType)
        return false;
      continue;
    }
    const auto &declaration = types.parameter(parameter);
    if (!potential || !types.isSymbolic(actual)) {
      if ((declaration.copyRequested && !types.isCopy(actual)) ||
          (declaration.sized && !types.isSized(actual)))
        return false;
      if (declaration.callableConstraint != Type::Unknown) {
        bool valid =
            callableProof
                ? callableProof(parameter, actual, bindings, regions, span)
                : types.satisfiesCallable(
                      actual,
                      normalize(substituted(declaration.callableConstraint), {},
                                span));
        if (!valid)
          return false;
      }
    }
  }
  std::vector<Obligation> requirements;
  for (auto requirement : implementation.requirements) {
    requirement.subject = substituted(requirement.subject);
    requirement.interfaceType = substituted(requirement.interfaceType);
    requirements.push_back(requirement);
    if (potential) {
      if (!types.isSymbolic(requirement.subject) &&
          ((requirement.property == Property::Copy &&
            !types.isCopy(requirement.subject)) ||
           (requirement.property == Property::Sized &&
            !types.isSized(requirement.subject)) ||
           (requirement.property == Property::Unpin &&
            !types.isUnpin(requirement.subject))))
        return false;
      // A concrete nominal subject only satisfies an interface requirement
      // when some implementation could apply to it.
      if (requirement.property == Property::Interface &&
          types.isErased(requirement.interfaceType) &&
          !types.isParameter(requirement.subject) &&
          !types.isProjection(requirement.subject) &&
          !types.isOpaque(requirement.subject) &&
          !types.isErased(requirement.subject) &&
          !someImplementationCouldApply(requirement.subject,
                                        requirement.interfaceType))
        return false;
    } else if (!prove(requirement, span, false))
      return false;
  }
  if (potential)
    for (std::size_t i = 0; i < requirements.size(); ++i)
      for (std::size_t j = 0; j < i; ++j) {
        const auto &left = requirements[i], &right = requirements[j];
        if (left.property != Property::Interface ||
            right.property != Property::Interface ||
            left.subject != right.subject ||
            !types.isErased(left.interfaceType) ||
            !types.isErased(right.interfaceType))
          continue;
        const auto a = types.erased(left.interfaceType);
        const auto b = types.erased(right.interfaceType);
        if (a.declaration != b.declaration || a.arguments != b.arguments)
          continue;
        std::vector<TypeBinding> associated;
        for (const auto &first : a.associated)
          for (const auto &second : b.associated)
            if (first.parameter == second.parameter)
              associated.push_back({first.argument, second.argument});
        if (!equalities(associated, implementation.parameters, bindings, span,
                        true))
          return false;
      }
  return true;
}

std::optional<std::vector<TypeBinding>>
Solver::applicable(const Implementation &implementation, Type self, Span span,
                   std::vector<RegionBinding> *selectedRegions, bool) {
  std::vector<TypeBinding> bindings;
  auto environment = regionEnvironment;
  auto scope = types.regions().binder(environment.universe);
  std::vector<RegionBinding> regions;
  for (auto parameter : implementation.regions)
    regions.push_back({parameter, types.regions().inference(scope)});
  auto pattern = types.substituteRegions(
      resolve(implementation.target, bindings, types), regions);
  auto matched = match(pattern, self, false, &environment);
  if (!matched) {
    if (regionInconclusive && !limitReported) {
      diagnostics.error("limit", span,
                        "implementation region solving is inconclusive");
      limitReported = true;
    }
    return std::nullopt;
  }
  for (const auto &binding : *matched)
    if (std::find(implementation.parameters.begin(),
                  implementation.parameters.end(),
                  binding.parameter) == implementation.parameters.end())
      return std::nullopt;
  bindings.insert(bindings.end(), matched->begin(), matched->end());
  for (auto &binding : regions)
    for (const auto &substitution : environment.substitutions)
      if (binding.argument == substitution.first)
        binding.argument = substitution.second;
  RegionSolver solver(types.regions());
  for (const auto &requirement : implementation.regionRequirements) {
    auto answer = solver.outlives(
        types.regions().substitute(requirement.longer, regions),
        types.regions().substitute(requirement.shorter, regions), environment);
    regionInconclusive |= answer == RegionAnswer::Inconclusive;
    if (answer != RegionAnswer::Proven) {
      if (answer == RegionAnswer::Inconclusive && !limitReported) {
        diagnostics.error("limit", span,
                          "implementation region solving is inconclusive");
        limitReported = true;
      }
      return std::nullopt;
    }
  }
  auto leak = solver.leakCheck(environment);
  if (leak != RegionAnswer::Proven) {
    regionInconclusive |= leak == RegionAnswer::Inconclusive;
    if (leak == RegionAnswer::Inconclusive && !limitReported) {
      diagnostics.error("limit", span,
                        "implementation region solving is inconclusive");
      limitReported = true;
    }
    return std::nullopt;
  }
  auto saved = regionEnvironment;
  regionEnvironment = environment;
  bool valid = constraints(implementation, bindings, span, regions);
  if (valid && selectedRegions)
    *selectedRegions = regions;
  regionEnvironment = std::move(saved);
  if (!valid && regionInconclusive && !limitReported) {
    diagnostics.error("limit", span,
                      "implementation constraint solving is inconclusive");
    limitReported = true;
  }
  return valid ? std::optional(std::move(bindings)) : std::nullopt;
}

bool Solver::someImplementationCouldApply(Type subject, Type interfaceType) {
  auto declaration = types.erased(interfaceType).declaration;
  for (auto position : candidatesFor(declaration))
    if (match(database.implementations[position].target, subject, true))
      return true;
  return false;
}

bool Solver::coherent() {
  bool valid = true;
  for (std::size_t i = 0; i < database.implementations.size(); ++i) {
    const auto &left = database.implementations[i];
    std::set<Type> known;
    for (auto parameter : identityParameters(left.target, types))
      known.insert(parameter);
    if (types.isErased(left.interfaceType))
      for (auto argument : types.erased(left.interfaceType).arguments)
        for (auto parameter : identityParameters(argument, types))
          known.insert(parameter);
    bool changed;
    do {
      auto count = known.size();
      for (const auto &equation : left.equalities) {
        if (determined(equation.parameter, left, known, types))
          for (auto parameter : identityParameters(equation.argument, types))
            known.insert(parameter);
        if (determined(equation.argument, left, known, types))
          for (auto parameter : identityParameters(equation.parameter, types))
            known.insert(parameter);
      }
      for (const auto &requirement : left.requirements) {
        if (requirement.property != Property::Interface ||
            !types.isErased(requirement.interfaceType) ||
            !determined(requirement.subject, left, known, types))
          continue;
        for (const auto &binding :
             types.erased(requirement.interfaceType).associated)
          for (auto parameter : identityParameters(binding.argument, types))
            known.insert(parameter);
      }
      for (auto parameter : left.parameters) {
        if (!known.contains(parameter) || !types.isParameter(parameter))
          continue;
        auto contract = types.parameter(parameter).callableConstraint;
        if (contract == Type::Unknown || !types.isFunctionPointer(contract))
          continue;
        for (auto result :
             {types.callable(contract).result, types.callable(contract).error})
          for (auto output : identityParameters(result, types))
            known.insert(output);
      }
      changed = count != known.size();
    } while (changed);
    for (auto parameter : left.parameters)
      if (!known.contains(parameter)) {
        diagnostics.error("type", left.span,
                          "unconstrained implementation parameter '" +
                              displayPath(types.name(parameter)) + "'");
        valid = false;
      }
    if (types.isErased(left.interfaceType)) {
      const auto &definition =
          database.definitions[types.erased(left.interfaceType).declaration];
      auto nominal = left.target;
      if (types.isProduct(nominal) &&
          types.product(nominal).genericOrigin != Type::Unknown)
        nominal = types.product(nominal).genericOrigin;
      bool localType =
          types.isProduct(nominal) &&
          (types.product(nominal).kind == AggregateKind::Product ||
           types.product(nominal).kind == AggregateKind::Enumeration ||
           types.product(nominal).kind == AggregateKind::Opaque) &&
          types.product(nominal).package == left.package;
      if (definition.package != left.package && !localType) {
        diagnostics.error("type", left.span,
                          "orphan interface implementation has no local owner");
        valid = false;
      }
    }
    for (std::size_t j = 0; j < i; ++j) {
      steps = 0;
      const auto &right = database.implementations[j];
      bool same = types.isErased(left.interfaceType) &&
                  types.isErased(right.interfaceType) &&
                  types.erased(left.interfaceType).declaration ==
                      types.erased(right.interfaceType).declaration;
      if (!same && !(left.interfaceType == Type::Unknown &&
                     right.interfaceType == Type::Unknown))
        continue;
      if (!same && std::none_of(left.inherent.begin(), left.inherent.end(),
                                [&](const auto &method) {
                                  return right.inherent.contains(method.first);
                                }))
        continue;
      std::vector<Type> a{left.target}, b{right.target};
      if (same) {
        const auto &first = types.erased(left.interfaceType).arguments;
        const auto &second = types.erased(right.interfaceType).arguments;
        a.insert(a.end(), first.begin(), first.end());
        b.insert(b.end(), second.begin(), second.end());
      }
      auto pattern = types.structural(AggregateKind::Tuple, std::move(a));
      auto actual = types.structural(AggregateKind::Tuple, std::move(b));
      auto bindings = match(pattern, actual, true);
      if (!bindings)
        continue;
      Implementation intersection = left;
      intersection.parameters.insert(intersection.parameters.end(),
                                     right.parameters.begin(),
                                     right.parameters.end());
      intersection.equalities.insert(intersection.equalities.end(),
                                     right.equalities.begin(),
                                     right.equalities.end());
      intersection.requirements.insert(intersection.requirements.end(),
                                       right.requirements.begin(),
                                       right.requirements.end());
      if (!constraints(intersection, *bindings, left.span, {}, true))
        continue;
      diagnostics.error(
          "type", left.span,
          "overlapping implementations cannot be selected by order");
      valid = false;
    }
  }
  return valid;
}
} // namespace mettle::interfaces
