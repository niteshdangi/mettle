#include "semantics/interfaces.h"
#include "support/limits.h"
#include "support/path.h"
#include <algorithm>
#include <array>
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
                        bool potential,
                        std::span<const TypeBinding> callableResults) {
  std::vector<TypeBinding> solved;
  for (const auto &binding : bindings)
    if (binding.argument != Type::Unknown)
      solved.push_back(binding);
  std::map<Type, Type> projected;
  for (std::size_t i = 0; i < equations.size() + callableResults.size(); ++i) {
    auto callableResult = i >= equations.size();
    const auto &equation =
        callableResult ? callableResults[i - equations.size()] : equations[i];
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
    // Callable result inference preserves regions; constraints proves them.
    auto *regions = potential || callableResult ? nullptr : &regionEnvironment;
    auto unified = match(left, right, true, regions);
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
      if (!inserted && !match(known->second, right, true, regions))
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
      const auto &associatedType = types.parameter(item->parameter);
      equations.push_back(
          {types.substituteRegions(
               types.projection(
                   requirement.subject, interfaceType,
                   static_cast<std::size_t>(item -
                                            definition.associated.begin()),
                   {}, associatedType.valueType, associatedType.copyRequested,
                   associatedType.sized, associatedType.regionArguments,
                   associatedType.thin),
               regions),
           types.substituteRegions(binding.argument, regions)});
    }
  }
  std::vector<TypeBinding> callableResults;
  for (auto parameter : implementation.parameters) {
    if (!types.isParameter(parameter))
      continue;
    auto contract = types.parameter(parameter).callableConstraint;
    auto actual = resolve(parameter, bindings, types);
    if (contract == Type::Unknown || actual == parameter ||
        !types.isCallable(actual))
      continue;
    callableResults.push_back(
        {types.callable(contract).result, types.callable(actual).result});
  }
  if (!equalities(equations, implementation.parameters, bindings, span,
                  potential, callableResults))
    return false;
  std::vector<RegionBinding> actualRegions(regions.begin(), regions.end());
  for (auto &binding : actualRegions)
    for (const auto &substitution : regionEnvironment.substitutions)
      if (binding.argument == substitution.first)
        binding.argument = substitution.second;
  auto substituted = [&](Type type) {
    return types.substituteRegions(resolve(type, bindings, types),
                                   actualRegions);
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
    // Substituting an array length or field type cannot make a fixed
    // non-callable outer shape callable.
    if (potential && declaration.callableConstraint != Type::Unknown &&
        !types.isCallable(actual) && !types.isParameter(actual) &&
        !types.isProjection(actual) && !types.isOpaque(actual) &&
        !types.isErased(actual))
      return false;
    if (!potential || !types.isSymbolic(actual)) {
      if ((declaration.copyRequested && !types.isCopy(actual)) ||
          (declaration.sized && !types.isSized(actual)))
        return false;
      if (declaration.callableConstraint != Type::Unknown) {
        auto proveCallable = [&] {
          if (callableProof)
            return callableProof(parameter, actual, bindings, actualRegions,
                                 span);
          auto expected =
              normalize(substituted(declaration.callableConstraint), {}, span);
          if (!types.isCallable(actual) || !types.isFunctionPointer(expected))
            return false;
          auto source = types.callableType(types.callable(actual));
          if (!types.satisfiesCallable(types.eraseRegions(source),
                                       types.eraseRegions(expected)))
            return false;
          if (revealOpaque)
            return true;
          RegionSolver proof(types.regions());
          RegionTypeSolver contracts(types, proof);
          auto answer = contracts.coerce(source, expected, regionEnvironment);
          regionInconclusive |= answer == RegionAnswer::Inconclusive;
          return answer == RegionAnswer::Proven;
        };
        if (!proveCallable())
          return false;
      }
    }
  }
  std::vector<Obligation> requirements;
  for (auto requirement : implementation.requirements) {
    auto elided = types.isView(requirement.subject)
                      ? types.view(requirement.subject).region
                      : RegionId::Unspecified;
    requirement.subject = normalize(substituted(requirement.subject), {}, span);
    requirement.interfaceType =
        normalize(substituted(requirement.interfaceType), {}, span);
    requirements.push_back(requirement);
    if (potential) {
      if (!types.isSymbolic(requirement.subject) &&
          ((requirement.property == Property::Copy &&
            !types.isCopy(requirement.subject)) ||
           (requirement.property == Property::Sized &&
            !types.isSized(requirement.subject)) ||
           (requirement.property == Property::Thin &&
            !types.isThin(requirement.subject)) ||
           (requirement.property == Property::Unpin &&
            !types.isUnpin(requirement.subject)) ||
           ((requirement.property == Property::UnwindSafe ||
             requirement.property == Property::RefUnwindSafe ||
             requirement.property == Property::Freeze) &&
            !proveStructuralProperty(requirement.property, requirement.subject,
                                     span))))
        return false;
      // Closed function-pointer markers can rule out known outer shapes even
      // when their generic arguments remain symbolic.
      if (requirement.property == Property::Interface &&
          types.isErased(requirement.interfaceType) &&
          requirement.subject != Type::Unknown &&
          !types.isParameter(requirement.subject) &&
          !types.isProjection(requirement.subject) &&
          !types.isOpaque(requirement.subject) &&
          !types.isErased(requirement.subject)) {
        const auto &name =
            database
                .definitions[types.erased(requirement.interfaceType)
                                 .declaration]
                .name;
        bool functionPointerMarker = name == "core::clone::FunctionPointer" ||
                                     name == "core::ops::FnPtr";
        bool knownStructuralShape =
            types.isView(requirement.subject) ||
            types.isPointer(requirement.subject) ||
            types.isSlice(requirement.subject) ||
            types.isFunctionPointer(requirement.subject);
        bool knownNominalShape = false;
        if (types.isProduct(requirement.subject)) {
          auto kind = types.product(requirement.subject).kind;
          knownStructuralShape |= kind != AggregateKind::Product &&
                                  kind != AggregateKind::Enumeration &&
                                  kind != AggregateKind::NativeVector &&
                                  kind != AggregateKind::Opaque;
          knownNominalShape = kind == AggregateKind::Product ||
                              kind == AggregateKind::Enumeration;
        }
        if ((functionPointerMarker || knownStructuralShape ||
             knownNominalShape || !types.isSymbolic(requirement.subject)) &&
            !someImplementationCouldApply(requirement.subject,
                                          requirement.interfaceType))
          return false;
      }
    } else {
      auto saved = regionEnvironment;
      if (types.regions().get(elided).kind == RegionKind::Inference) {
        auto scope = types.regions().binder(regionEnvironment.universe, true);
        regionEnvironment.universe = scope.universe;
        // An elided borrowed subject must work for any caller borrow.
        RegionBinding fresh{elided,
                            types.regions().rigid(scope, "<elided-bound>")};
        requirement.subject =
            types.substituteRegions(requirement.subject, {&fresh, 1});
        requirement.interfaceType =
            types.substituteRegions(requirement.interfaceType, {&fresh, 1});
      }
      bool holds = prove(requirement, span, false);
      regionEnvironment = std::move(saved);
      if (!holds)
        return false;
    }
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
                   std::vector<RegionBinding> *selectedRegions, bool,
                   bool potential) {
  if (implementation.target.index() < builtinTypeCount &&
      implementation.target != self)
    return std::nullopt;
  auto origin = types.nominalOrigin(implementation.target);
  if (origin != Type::Unknown && origin != types.nominalOrigin(self))
    return std::nullopt;
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
  auto saved = std::move(regionEnvironment);
  regionEnvironment = std::move(environment);
  bool valid = constraints(implementation, bindings, span, regions, potential);
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
  const auto &definition = database.definitions[declaration];
  if (definition.name == "core::clone::FunctionPointer" ||
      definition.name == "core::ops::FnPtr")
    return types.isFunctionPointer(subject);
  auto owner = subject;
  while (types.isView(owner))
    owner = types.view(owner).payload;
  while (types.isProduct(owner)) {
    const auto &record = types.product(owner);
    if (record.regionOrigin != Type::Unknown)
      owner = record.regionOrigin;
    else if (record.genericOrigin != Type::Unknown)
      owner = record.genericOrigin;
    else
      break;
  }
  // Unknown owners can become downstream-local types, permitting new impls.
  if (definition.package == unknownPackage || owner == Type::Unknown ||
      types.isParameter(owner) || types.isProjection(owner) ||
      types.isOpaque(owner) || types.isErased(owner))
    return true;
  if (types.isProduct(owner)) {
    const auto &record = types.product(owner);
    if ((record.kind == AggregateKind::Product ||
         record.kind == AggregateKind::Enumeration) &&
        record.package == unknownPackage)
      return true;
  }
  auto key = std::pair(subject, interfaceType);
  // Recursive requirements cannot establish that two implementations are
  // disjoint.
  if (!active.insert(key).second)
    return true;
  struct PotentialScope {
    std::set<std::pair<Type, Type>> &active;
    std::pair<Type, Type> key;
    ~PotentialScope() { active.erase(key); }
  } scope{active, key};
  if (active.size() >= limits::typeDepth) {
    if (!limitReported) {
      diagnostics.error("limit", database.definitions[declaration].span,
                        "interface coherence nesting limit exceeded");
      limitReported = true;
    }
    return true;
  }
  for (auto position : database.implementationsFor(types, declaration)) {
    const auto &candidate = database.implementations[position];
    std::vector<Type> pattern{candidate.target}, actual{subject};
    const auto &offered = types.erased(candidate.interfaceType).arguments;
    const auto &requested = types.erased(interfaceType).arguments;
    pattern.insert(pattern.end(), offered.begin(), offered.end());
    actual.insert(actual.end(), requested.begin(), requested.end());
    auto bindings =
        match(types.structural(AggregateKind::Tuple, std::move(pattern)),
              types.structural(AggregateKind::Tuple, std::move(actual)), true);
    if (bindings && constraints(candidate, *bindings, candidate.span, {}, true))
      return true;
  }
  return false;
}

bool Solver::coherent() {
  bool imported = true;
  for (std::size_t i = 0; i < database.implementations.size(); ++i)
    if (!database.importedImplementation(i)) {
      imported = false;
      break;
    }
  if (imported)
    return true;
  bool valid = true;
  using InterfaceKey = std::pair<std::uint32_t, bool>;
  using MethodKey = std::pair<std::string, bool>;
  std::array<std::map<InterfaceKey, std::vector<std::size_t>>, 2> interfaces;
  std::array<std::map<MethodKey, std::vector<std::size_t>>, 2> methods;
  for (std::size_t i = 0; i < database.implementations.size(); ++i) {
    if (database.importedImplementations &&
        i < database.importedImplementations->size() &&
        !database.implementations.isMaterialized(i)) {
      const auto &header = (*database.importedImplementations)[i];
      bool relevant = false;
      if (header.interfaceDeclaration != UINT32_MAX) {
        auto key = InterfaceKey{header.interfaceDeclaration, header.fallback};
        auto found = interfaces[1].find(key);
        relevant = found != interfaces[1].end() && !found->second.empty();
        if (!relevant)
          interfaces[0][key].push_back(i);
      } else if (header.interfaceType == Type::Unknown) {
        for (const auto &name : header.inherent) {
          auto found = methods[1].find({name, header.fallback});
          relevant |= found != methods[1].end() && !found->second.empty();
        }
        if (!relevant)
          for (const auto &name : header.inherent)
            methods[0][{name, header.fallback}].push_back(i);
      }
      if (!relevant)
        continue;
    }
    const auto &left = database.implementations[i];
    if (!left.checkedImport) {
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
          for (auto result : {types.callable(contract).result,
                              types.callable(contract).error})
            for (auto output : identityParameters(result, types))
              known.insert(output);
        }
        changed = count != known.size();
      } while (changed);
      for (auto parameter : left.parameters)
        if (!known.contains(parameter)) {
          diagnostics.error("type", left.span,
                            "unconstrained implementation parameter '" +
                                displayType(types, parameter) + "'");
          valid = false;
        }
      if (types.isErased(left.interfaceType)) {
        const auto &definition =
            database.definitions[types.erased(left.interfaceType).declaration];
        auto nominal = left.target;
        while (types.isView(nominal))
          nominal = types.view(nominal).payload;
        if (types.isProduct(nominal) &&
            types.product(nominal).genericOrigin != Type::Unknown)
          nominal = types.product(nominal).genericOrigin;
        bool localType =
            left.package != unknownPackage && types.isProduct(nominal) &&
            (types.product(nominal).kind == AggregateKind::Product ||
             types.product(nominal).kind == AggregateKind::Enumeration ||
             types.product(nominal).kind == AggregateKind::Opaque) &&
            types.product(nominal).package == left.package;
        bool localInterface = left.package != unknownPackage &&
                              definition.package == left.package;
        if (!localInterface && !localType) {
          diagnostics.error(
              "type", left.span,
              "orphan interface implementation has no local owner");
          valid = false;
        }
      }
    }
    const auto category = left.checkedImport ? 1 : 0;
    std::vector<std::size_t> inherent;
    const std::vector<std::size_t> *candidates = &inherent;
    if (types.isErased(left.interfaceType))
      candidates = &interfaces[category][{
          types.erasedDeclaration(left.interfaceType), left.fallback}];
    else if (left.interfaceType == Type::Unknown) {
      for (const auto &[name, method] : left.inherent) {
        (void)method;
        auto found = methods[category].find({name, left.fallback});
        if (found != methods[category].end())
          inherent.insert(inherent.end(), found->second.begin(),
                          found->second.end());
      }
      std::sort(inherent.begin(), inherent.end());
      inherent.erase(std::unique(inherent.begin(), inherent.end()),
                     inherent.end());
    }
    for (auto j : *candidates) {
      steps = 0;
      const auto &right = database.implementations[j];
      bool same = types.isErased(left.interfaceType) &&
                  types.isErased(right.interfaceType);
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
          "overlapping implementations cannot be selected by order",
          {{"note", right.span,
            "conflicting implementation is declared here"}});
      valid = false;
    }
    for (std::size_t pool = 0; pool < (left.checkedImport ? 1u : 2u); ++pool)
      if (types.isErased(left.interfaceType))
        interfaces[pool]
                  [{types.erasedDeclaration(left.interfaceType), left.fallback}]
                      .push_back(i);
      else if (left.interfaceType == Type::Unknown)
        for (const auto &[name, method] : left.inherent) {
          (void)method;
          methods[pool][{name, left.fallback}].push_back(i);
        }
  }
  return valid;
}
} // namespace mettle::interfaces
