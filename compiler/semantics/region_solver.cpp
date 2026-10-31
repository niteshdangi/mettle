#include "semantics/region_solver.h"
#include <algorithm>

namespace mettle {
bool requiresRegionProof(Type type, const TypeStore &types) {
  std::vector<Type> active;
  auto visit = [&](auto &&self, Type nested) -> bool {
    if (std::find(active.begin(), active.end(), nested) != active.end())
      return true;
    active.push_back(nested);
    bool result = types.isView(nested) || types.isProjection(nested);
    if (types.isCallable(nested)) {
      const auto &contract = types.callable(nested);
      result |= !contract.regions.empty() ||
                !contract.regionParameters.empty() ||
                !contract.regionRequirements.empty() ||
                self(self, contract.result) || self(self, contract.error);
      for (const auto &parameter : contract.parameters)
        result |= parameter.mode == ParameterMode::Read ||
                  parameter.mode == ParameterMode::Mut ||
                  self(self, parameter.type);
    } else if (types.isProduct(nested)) {
      const auto &record = types.product(nested);
      if (record.kind == AggregateKind::Array && !record.components.empty())
        result |= self(self, record.components[0]);
      else
        for (const auto &field : record.fields)
          result |= self(self, field.type);
    } else if (types.isErased(nested)) {
      const auto &descriptor = types.erased(nested);
      result |= !descriptor.regionArguments.empty() ||
                !descriptor.regionParameters.empty();
      for (auto argument : descriptor.arguments)
        result |= self(self, argument);
    }
    active.pop_back();
    return result;
  };
  return visit(visit, type);
}
RegionId RegionSolver::resolve(RegionId region,
                               const RegionEnvironment &environment,
                               std::size_t &remaining) const {
  while (remaining) {
    --remaining;
    auto found = std::find_if(
        environment.substitutions.begin(), environment.substitutions.end(),
        [&](const auto &binding) { return binding.first == region; });
    if (found == environment.substitutions.end())
      return region;
    region = found->second;
  }
  return RegionId::Unspecified;
}
RegionAnswer RegionSolver::instantiate(RegionId variable, RegionId value,
                                       RegionEnvironment &environment) const {
  if (regions.get(variable).kind != RegionKind::Inference)
    return RegionAnswer::Rejected;
  std::size_t remaining = budget;
  value = resolve(value, environment, remaining);
  if (!remaining)
    return RegionAnswer::Inconclusive;
  if (variable == value)
    return RegionAnswer::Proven;
  auto occurs = [&](auto &&self, RegionId nested) -> bool {
    if (!remaining)
      return true;
    --remaining;
    nested = resolve(nested, environment, remaining);
    if (nested == variable)
      return true;
    const auto &record = regions.get(nested);
    for (auto source : record.sources)
      if (self(self, source))
        return true;
    return false;
  };
  auto recursive = occurs(occurs, value);
  if (!remaining)
    return RegionAnswer::Inconclusive;
  if (recursive)
    return RegionAnswer::Rejected;
  if (!regions.visible(value, regions.get(variable).universe))
    return RegionAnswer::Rejected;
  auto found = std::find_if(
      environment.substitutions.begin(), environment.substitutions.end(),
      [&](const auto &binding) { return binding.first == variable; });
  if (found != environment.substitutions.end())
    return found->second == value ? RegionAnswer::Proven
                                  : RegionAnswer::Rejected;
  environment.substitutions.emplace_back(variable, value);
  return leakCheck(environment);
}
RegionAnswer
RegionSolver::leakCheck(const RegionEnvironment &environment) const {
  std::map<RegionId, RegionId> unique;
  for (const auto &[variable, value] : environment.substitutions) {
    if (regions.get(variable).kind != RegionKind::Inference)
      return RegionAnswer::Rejected;
    auto [prior, inserted] = unique.emplace(variable, value);
    if (!inserted && prior->second != value)
      return RegionAnswer::Rejected;
    std::size_t remaining = budget;
    auto resolved = resolve(value, environment, remaining);
    if (!remaining)
      return RegionAnswer::Inconclusive;
    if (!regions.visible(resolved, regions.get(variable).universe))
      return RegionAnswer::Rejected;
  }
  for (const auto &edge : environment.assumptions)
    if (!regions.visible(edge.longer, environment.universe) ||
        !regions.visible(edge.shorter, environment.universe))
      return RegionAnswer::Rejected;
  return RegionAnswer::Proven;
}
RegionAnswer RegionSolver::prove(RegionId longer, RegionId shorter,
                                 const RegionEnvironment &environment,
                                 std::vector<RegionOutlives> &active,
                                 std::size_t &remaining) const {
  longer = resolve(longer, environment, remaining);
  shorter = resolve(shorter, environment, remaining);
  if (!remaining)
    return RegionAnswer::Inconclusive;
  if (longer == RegionId::Unspecified || shorter == RegionId::Unspecified)
    return RegionAnswer::Rejected;
  if (longer == shorter || longer == RegionId::Static)
    return RegionAnswer::Proven;
  const auto &left = regions.get(longer), &right = regions.get(shorter);
  if (left.kind == RegionKind::Local && right.kind == RegionKind::Local &&
      left.binder == right.binder)
    return RegionAnswer::Proven;
  if (left.kind == RegionKind::Intersection) {
    for (auto source : left.sources) {
      auto result = prove(source, shorter, environment, active, remaining);
      if (result != RegionAnswer::Proven)
        return result;
    }
    return RegionAnswer::Proven;
  }
  if (right.kind == RegionKind::Intersection) {
    // A source supports the intersection if it supports at least one member;
    // the intersection itself is valid only where all members remain valid.
    bool inconclusive = false;
    for (auto source : right.sources) {
      auto result = prove(longer, source, environment, active, remaining);
      if (result == RegionAnswer::Proven)
        return result;
      inconclusive |= result == RegionAnswer::Inconclusive;
    }
    return inconclusive ? RegionAnswer::Inconclusive : RegionAnswer::Rejected;
  }
  RegionOutlives goal{longer, shorter};
  if (std::find(active.begin(), active.end(), goal) != active.end())
    return RegionAnswer::Inconclusive;
  active.push_back(goal);
  bool inconclusive = false;
  for (const auto &edge : environment.assumptions) {
    auto source = resolve(edge.longer, environment, remaining);
    if (!remaining) {
      active.pop_back();
      return RegionAnswer::Inconclusive;
    }
    if (source != longer)
      continue;
    auto result = prove(edge.shorter, shorter, environment, active, remaining);
    if (result == RegionAnswer::Proven) {
      active.pop_back();
      return result;
    }
    inconclusive |= result == RegionAnswer::Inconclusive;
  }
  active.pop_back();
  return inconclusive ? RegionAnswer::Inconclusive : RegionAnswer::Rejected;
}
RegionAnswer RegionSolver::outlives(RegionId longer, RegionId shorter,
                                    const RegionEnvironment &environment) {
  auto assumptions = environment.assumptions;
  auto substitutions = environment.substitutions;
  std::sort(assumptions.begin(), assumptions.end());
  std::sort(substitutions.begin(), substitutions.end());
  Key key{longer, shorter, environment.universe, std::move(assumptions),
          std::move(substitutions)};
  if (auto found = cache.find(key); found != cache.end())
    return found->second;
  auto result = leakCheck(environment);
  if (!regions.visible(longer, environment.universe) ||
      !regions.visible(shorter, environment.universe))
    result = RegionAnswer::Rejected;
  if (result == RegionAnswer::Proven) {
    std::size_t remaining = budget;
    std::vector<RegionOutlives> active;
    result = prove(longer, shorter, environment, active, remaining);
  }
  cache.emplace(std::move(key), result);
  return result;
}
namespace {
RegionAnswer together(RegionAnswer left, RegionAnswer right) {
  if (left == RegionAnswer::Rejected || right == RegionAnswer::Rejected)
    return RegionAnswer::Rejected;
  return left == RegionAnswer::Inconclusive ||
                 right == RegionAnswer::Inconclusive
             ? RegionAnswer::Inconclusive
             : RegionAnswer::Proven;
}
Type nominalOrigin(const TypeStore &types, Type type) {
  while (types.isProduct(type)) {
    const auto &product = types.product(type);
    auto origin = product.regionOrigin != Type::Unknown ? product.regionOrigin
                                                        : product.genericOrigin;
    if (origin == Type::Unknown)
      break;
    type = origin;
  }
  return type;
}
Variance combine(Variance left, Variance right) {
  if (left == Variance::Bivariant)
    return right;
  if (right == Variance::Bivariant || left == right)
    return left;
  return Variance::Invariant;
}
Variance reverse(Variance value) {
  return value == Variance::Covariant       ? Variance::Contravariant
         : value == Variance::Contravariant ? Variance::Covariant
                                            : value;
}
} // namespace
RegionAnswer RegionTypeSolver::compare(
    Type source, Type target, const RegionEnvironment &environment,
    std::vector<std::pair<Type, Type>> &active, std::size_t &remaining) {
  if (!remaining)
    return RegionAnswer::Inconclusive;
  --remaining;
  if (source == target || source == Type::Never)
    return RegionAnswer::Proven;
  if (source == Type::Unknown || target == Type::Unknown)
    return RegionAnswer::Inconclusive;
  auto goal = std::pair{source, target};
  if (std::find(active.begin(), active.end(), goal) != active.end())
    // A cycle through a recursive nominal type or raw pointer holds
    // coinductively; every other obligation is checked by the outer frames.
    return (types.isPointer(source) && types.isPointer(target)) ||
                   (types.isProduct(source) && types.isProduct(target))
               ? RegionAnswer::Proven
               : RegionAnswer::Inconclusive;
  active.push_back(goal);
  RegionAnswer answer = RegionAnswer::Rejected;
  if (types.isView(source) && types.isView(target)) {
    const auto &from = types.view(source), &to = types.view(target);
    if (from.mode == to.mode || to.mode == ParameterMode::Read) {
      answer = regions.outlives(from.region, to.region, environment);
      answer = together(answer, compare(from.payload, to.payload, environment,
                                        active, remaining));
      if (to.mode == ParameterMode::Mut)
        answer = together(answer, compare(to.payload, from.payload, environment,
                                          active, remaining));
    }
  } else if (types.isPointer(source) && types.isPointer(target)) {
    // Raw pointers carry no region; their pointee is checked like a view
    // payload, so equal pointees reached through distinct type ids match.
    const auto &from = types.pointer(source), &to = types.pointer(target);
    if (from.mode == to.mode) {
      answer =
          compare(from.payload, to.payload, environment, active, remaining);
      if (to.mode == ParameterMode::Mut)
        answer = together(answer, compare(to.payload, from.payload, environment,
                                          active, remaining));
    }
  } else if (types.isSlice(source) && types.isSlice(target))
    answer = compare(types.slice(source).element, types.slice(target).element,
                     environment, active, remaining);
  else if (types.isProduct(source) && types.isProduct(target)) {
    const auto &from = types.product(source), &to = types.product(target);
    if (from.regionPattern != Type::Unknown &&
        from.regionPattern == to.regionPattern &&
        from.regionArguments.size() ==
            types.product(from.regionPattern).regionArguments.size() &&
        from.genericArguments.size() ==
            types.product(from.regionPattern).genericArguments.size() &&
        to.regionArguments.size() == from.regionArguments.size() &&
        to.genericArguments.size() == from.genericArguments.size()) {
      auto pattern = types.product(from.regionPattern);
      answer = RegionAnswer::Proven;
      for (std::size_t i = 0; i < from.regionArguments.size(); ++i) {
        auto variance =
            varianceFor(from.regionPattern, pattern.regionArguments[i],
                        Type::Unknown, remaining);
        if (!variance) {
          answer = RegionAnswer::Inconclusive;
          break;
        }
        if (*variance == Variance::Covariant ||
            *variance == Variance::Invariant)
          answer = together(answer, regions.outlives(from.regionArguments[i],
                                                     to.regionArguments[i],
                                                     environment));
        if (*variance == Variance::Contravariant ||
            *variance == Variance::Invariant)
          answer = together(answer, regions.outlives(to.regionArguments[i],
                                                     from.regionArguments[i],
                                                     environment));
      }
      for (std::size_t i = 0; i < from.genericArguments.size(); ++i) {
        if (types.isConstant(pattern.genericArguments[i])) {
          if (from.genericArguments[i] != to.genericArguments[i])
            answer = RegionAnswer::Rejected;
          continue;
        }
        auto variance = varianceFor(from.regionPattern, RegionId::Unspecified,
                                    pattern.genericArguments[i], remaining);
        if (!variance) {
          answer = together(answer, RegionAnswer::Inconclusive);
          break;
        }
        // An owner holds its payload behind a raw pointer, yet owns it like
        // a field: the payload is covariant, as for any owned value.
        if (i == 0 && *variance == Variance::Bivariant &&
            from.genericOrigin != Type::Unknown &&
            !ownerSpelling(types.product(from.genericOrigin).name).empty())
          variance = Variance::Covariant;
        if (*variance == Variance::Covariant ||
            *variance == Variance::Invariant)
          answer = together(answer, compare(from.genericArguments[i],
                                            to.genericArguments[i], environment,
                                            active, remaining));
        if (*variance == Variance::Contravariant ||
            *variance == Variance::Invariant)
          answer = together(answer, compare(to.genericArguments[i],
                                            from.genericArguments[i],
                                            environment, active, remaining));
      }
      active.pop_back();
      return answer;
    }
    bool structural =
        from.kind == AggregateKind::Optional ||
        from.kind == AggregateKind::Outcome ||
        from.kind == AggregateKind::Tuple ||
        from.kind == AggregateKind::Array ||
        from.kind == AggregateKind::Range || from.kind == AggregateKind::Cell ||
        from.kind == AggregateKind::RefCell ||
        from.kind == AggregateKind::UnsafeCell ||
        from.kind == AggregateKind::Uninit ||
        from.kind == AggregateKind::ManualDrop ||
        from.kind == AggregateKind::Ref || from.kind == AggregateKind::RefMut ||
        from.kind == AggregateKind::Pin;
    if (from.kind == to.kind && from.fields.size() == to.fields.size() &&
        !structural && from.regionArguments.empty() &&
        to.regionArguments.empty() && from.genericArguments.empty() &&
        to.genericArguments.empty() &&
        nominalOrigin(types, source) == nominalOrigin(types, target)) {
      // A nominal type without region or generic arguments has fixed region
      // content; distinct decorations (for example through a self-referential
      // function-pointer field) are the same type.
      active.pop_back();
      return RegionAnswer::Proven;
    }
    if (from.kind == to.kind && from.fields.size() == to.fields.size() &&
        (structural ||
         nominalOrigin(types, source) == nominalOrigin(types, target))) {
      answer = RegionAnswer::Proven;
      if (from.kind == AggregateKind::Array) {
        answer = from.arrayCount == to.arrayCount &&
                         from.components.size() == 1 &&
                         to.components.size() == 1
                     ? compare(from.components[0], to.components[0],
                               environment, active, remaining)
                     : RegionAnswer::Rejected;
        active.pop_back();
        return answer;
      }
      for (std::size_t i = 0; i < from.fields.size(); ++i) {
        answer =
            together(answer, compare(from.fields[i].type, to.fields[i].type,
                                     environment, active, remaining));
        if (from.kind == AggregateKind::Cell ||
            from.kind == AggregateKind::RefCell ||
            from.kind == AggregateKind::UnsafeCell)
          answer =
              together(answer, compare(to.fields[i].type, from.fields[i].type,
                                       environment, active, remaining));
      }
    }
  } else if (types.isErased(source) && types.isErased(target)) {
    const auto from = types.erased(source), to = types.erased(target);
    if (from.declaration == to.declaration &&
        from.arguments.size() == to.arguments.size() &&
        from.regionArguments.size() == to.regionArguments.size() &&
        from.associated.size() == to.associated.size()) {
      answer = RegionAnswer::Proven;
      if (from.bound != RegionId::Unspecified &&
          to.bound != RegionId::Unspecified)
        answer = regions.outlives(from.bound, to.bound, environment);
      boundRejected |= answer == RegionAnswer::Rejected;
      for (std::size_t p = 0; p < from.regionArguments.size(); ++p) {
        answer = together(answer,
                          regions.outlives(from.regionArguments[p],
                                           to.regionArguments[p], environment));
        answer = together(answer, regions.outlives(to.regionArguments[p],
                                                   from.regionArguments[p],
                                                   environment));
      }
      for (std::size_t p = 0; p < from.arguments.size(); ++p) {
        if (types.isConstant(from.arguments[p]) ||
            types.isConstant(to.arguments[p])) {
          if (from.arguments[p] != to.arguments[p])
            answer = RegionAnswer::Rejected;
        } else {
          answer = together(answer, compare(from.arguments[p], to.arguments[p],
                                            environment, active, remaining));
          answer = together(answer, compare(to.arguments[p], from.arguments[p],
                                            environment, active, remaining));
        }
      }
      for (std::size_t p = 0; p < from.associated.size(); ++p) {
        if (from.associated[p].parameter != to.associated[p].parameter)
          answer = RegionAnswer::Rejected;
        else if (types.isConstant(from.associated[p].argument)) {
          if (from.associated[p].argument != to.associated[p].argument)
            answer = RegionAnswer::Rejected;
        } else {
          answer = together(answer, compare(from.associated[p].argument,
                                            to.associated[p].argument,
                                            environment, active, remaining));
          answer = together(answer, compare(to.associated[p].argument,
                                            from.associated[p].argument,
                                            environment, active, remaining));
        }
      }
    }
  } else if (types.isFunctionPointer(source) &&
             types.isFunctionPointer(target)) {
    answer = callable(source, target, environment, active, remaining);
  }
  active.pop_back();
  return answer;
}
Type RegionTypeSolver::substitute(
    Type type, const std::vector<std::pair<RegionId, RegionId>> &bindings) {
  std::vector<Type> active;
  auto region = [&](auto &&self, RegionId value) -> RegionId {
    for (const auto &binding : bindings)
      if (binding.first == value)
        return binding.second;
    auto record = types.regions().get(value);
    if (record.kind == RegionKind::Intersection) {
      for (auto &source : record.sources)
        source = self(self, source);
      return types.regions().intersection(std::move(record.sources));
    }
    return value;
  };
  auto visit = [&](auto &&self, Type nested) -> Type {
    if (active.size() >= 128 ||
        std::find(active.begin(), active.end(), nested) != active.end())
      return nested;
    active.push_back(nested);
    auto result = nested;
    if (types.isView(nested)) {
      auto view = types.view(nested);
      result = types.viewType(self(self, view.payload), view.mode,
                              region(region, view.region));
    } else if (types.isProduct(nested)) {
      auto product = types.product(nested);
      if (product.kind == AggregateKind::Array && !product.components.empty()) {
        auto element = self(self, product.components[0]);
        result = product.arrayCount == Type::Unknown
                     ? types.structural(AggregateKind::Array, {element},
                                        product.fields.size())
                     : types.arrayType(element, product.arrayCount);
        active.pop_back();
        return result;
      }
      for (auto &field : product.fields)
        field.type = self(self, field.type);
      for (auto &argument : product.regionArguments)
        argument = region(region, argument);
      result = types.regionalProduct(nested, std::move(product.fields),
                                     std::move(product.regionArguments));
    }
    active.pop_back();
    return result;
  };
  return visit(visit, type);
}
RegionAnswer RegionTypeSolver::callable(
    Type source, Type target, const RegionEnvironment &environment,
    std::vector<std::pair<Type, Type>> &active, std::size_t &remaining) {
  auto from = types.callable(source), to = types.callable(target);
  if (from.parameters.size() != to.parameters.size() ||
      (from.mode == ParameterMode::Take && to.mode != ParameterMode::Take) ||
      (from.mode == ParameterMode::Mut && to.mode == ParameterMode::Read))
    return RegionAnswer::Rejected;
  auto scope = types.regions().binder(environment.universe, true);
  auto inner = environment;
  inner.universe = scope.universe;
  std::vector<std::pair<RegionId, RegionId>> sourceBindings, targetBindings;
  for (auto parameter : from.regionParameters)
    sourceBindings.emplace_back(parameter, types.regions().inference(scope));
  for (auto parameter : to.regionParameters)
    targetBindings.emplace_back(
        parameter, types.regions().rigid(scope, "<higher-ranked>"));
  auto replaceRegion = [](RegionId value, const auto &bindings) {
    for (const auto &binding : bindings)
      if (binding.first == value)
        return binding.second;
    return value;
  };
  for (auto &parameter : from.parameters)
    parameter.type = substitute(parameter.type, sourceBindings);
  for (auto &parameter : to.parameters)
    parameter.type = substitute(parameter.type, targetBindings);
  from.result = substitute(from.result, sourceBindings);
  to.result = substitute(to.result, targetBindings);
  from.error = substitute(from.error, sourceBindings);
  to.error = substitute(to.error, targetBindings);
  for (auto &region : from.parameterRegions)
    region = replaceRegion(region, sourceBindings);
  for (auto &region : to.parameterRegions)
    region = replaceRegion(region, targetBindings);
  for (const auto &requirement : to.regionRequirements)
    inner.assumptions.push_back(
        {replaceRegion(requirement.longer, targetBindings),
         replaceRegion(requirement.shorter, targetBindings)});
  std::vector<Type> wellformed;
  auto supportsBorrow = [&](auto &&self, Type type, RegionId borrow) -> void {
    if (std::find(wellformed.begin(), wellformed.end(), type) !=
        wellformed.end())
      return;
    wellformed.push_back(type);
    if (types.isView(type)) {
      inner.assumptions.push_back({types.view(type).region, borrow});
      self(self, types.view(type).payload, borrow);
    } else if (types.isProduct(type)) {
      const auto &record = types.product(type);
      if (record.kind == AggregateKind::Array && !record.components.empty())
        self(self, record.components[0], borrow);
      else
        for (const auto &field : record.fields)
          self(self, field.type, borrow);
    }
    wellformed.pop_back();
  };
  for (std::size_t i = 0;
       i < to.parameters.size() && i < to.parameterRegions.size(); ++i)
    if (to.parameters[i].mode == ParameterMode::Read ||
        to.parameters[i].mode == ParameterMode::Mut)
      supportsBorrow(supportsBorrow, to.parameters[i].type,
                     to.parameterRegions[i]);
  std::vector<std::pair<RegionId, RegionId>> inferred;
  auto inferRegion = [&](RegionId variable, RegionId value) {
    if (types.regions().get(variable).kind != RegionKind::Inference)
      return;
    for (auto &binding : inferred)
      if (binding.first == variable) {
        binding.second = types.regions().intersection({binding.second, value});
        return;
      }
    inferred.emplace_back(variable, value);
  };
  std::vector<std::pair<Type, Type>> inferring;
  auto inferType = [&](auto &&self, Type pattern, Type actual) -> void {
    auto pair = std::pair{pattern, actual};
    if (inferring.size() >= 128 ||
        std::find(inferring.begin(), inferring.end(), pair) != inferring.end())
      return;
    inferring.push_back(pair);
    if (types.isView(pattern) && types.isView(actual)) {
      inferRegion(types.view(pattern).region, types.view(actual).region);
      self(self, types.view(pattern).payload, types.view(actual).payload);
    } else if (types.isProduct(pattern) && types.isProduct(actual)) {
      auto p = types.product(pattern), a = types.product(actual);
      if (p.kind == AggregateKind::Array && a.kind == AggregateKind::Array &&
          p.components.size() == 1 && a.components.size() == 1)
        self(self, p.components[0], a.components[0]);
      else if (p.fields.size() == a.fields.size())
        for (std::size_t i = 0; i < p.fields.size(); ++i)
          self(self, p.fields[i].type, a.fields[i].type);
    }
    inferring.pop_back();
  };
  for (std::size_t i = 0; i < from.parameters.size(); ++i) {
    if (from.parameters[i].mode != to.parameters[i].mode)
      return RegionAnswer::Rejected;
    inferType(inferType, from.parameters[i].type, to.parameters[i].type);
    if (i < from.parameterRegions.size() && i < to.parameterRegions.size())
      inferRegion(from.parameterRegions[i], to.parameterRegions[i]);
  }
  for (const auto &[variable, value] : inferred) {
    auto answer = regions.instantiate(variable, value, inner);
    if (answer != RegionAnswer::Proven)
      return answer;
  }
  auto answer = RegionAnswer::Proven;
  for (const auto &requirement : from.regionRequirements)
    answer = together(
        answer, regions.outlives(
                    replaceRegion(requirement.longer, sourceBindings),
                    replaceRegion(requirement.shorter, sourceBindings), inner));
  answer = together(answer,
                    compare(from.result, to.result, inner, active, remaining));
  answer =
      together(answer, compare(from.error, to.error, inner, active, remaining));
  for (std::size_t i = 0; i < from.parameters.size(); ++i) {
    answer =
        together(answer, compare(to.parameters[i].type, from.parameters[i].type,
                                 inner, active, remaining));
    if (from.parameters[i].mode == ParameterMode::Mut)
      answer = together(answer,
                        compare(from.parameters[i].type, to.parameters[i].type,
                                inner, active, remaining));
    if ((from.parameters[i].mode == ParameterMode::Read ||
         from.parameters[i].mode == ParameterMode::Mut) &&
        i < from.parameterRegions.size() && i < to.parameterRegions.size())
      answer =
          together(answer, regions.outlives(to.parameterRegions[i],
                                            from.parameterRegions[i], inner));
  }
  return together(answer, regions.leakCheck(inner));
}
RegionAnswer RegionTypeSolver::coerce(Type source, Type target,
                                      const RegionEnvironment &environment) {
  std::vector<std::pair<Type, Type>> active;
  std::size_t remaining = 4096;
  boundRejected = false;
  return compare(source, target, environment, active, remaining);
}
Variance RegionTypeSolver::variance(Type type, RegionId parameter) const {
  std::size_t remaining = 4096;
  return varianceFor(type, parameter, Type::Unknown, remaining)
      .value_or(Variance::Invariant);
}
std::optional<Variance>
RegionTypeSolver::varianceFor(Type type, RegionId region, Type parameter,
                              std::size_t &remaining) const {
  std::map<Type, Variance> values;
  std::map<Type, std::vector<Type>> parents;
  std::vector<Type> pending{type};
  auto children = [&](Type nested) {
    std::vector<Type> result;
    if (nested == parameter)
      return result;
    if (types.isView(nested))
      result.push_back(types.view(nested).payload);
    else if (types.isSlice(nested))
      result.push_back(types.slice(nested).element);
    else if (types.isProduct(nested)) {
      const auto &record = types.product(nested);
      for (const auto &field : record.fields)
        result.push_back(field.type);
      result.insert(result.end(), record.components.begin(),
                    record.components.end());
    } else if (types.isFunctionPointer(nested)) {
      const auto &contract = types.callable(nested);
      result = {contract.result, contract.error};
      for (const auto &input : contract.parameters)
        result.push_back(input.type);
    } else if (types.isErased(nested))
      result = types.erased(nested).arguments;
    else if (types.isProjection(nested))
      result = types.parameter(nested).operands;
    std::sort(result.begin(), result.end());
    result.erase(std::unique(result.begin(), result.end()), result.end());
    return result;
  };
  while (!pending.empty()) {
    if (!remaining)
      return std::nullopt;
    --remaining;
    auto nested = pending.back();
    pending.pop_back();
    if (!values.emplace(nested, Variance::Bivariant).second)
      continue;
    for (auto child : children(nested)) {
      parents[child].push_back(nested);
      pending.push_back(child);
    }
  }
  auto occurrence = [&](RegionId value) {
    if (region == RegionId::Unspecified)
      return false;
    const auto &record = types.regions().get(value);
    return value == region ||
           std::find(record.sources.begin(), record.sources.end(), region) !=
               record.sources.end();
  };
  for (const auto &[nested, value] : values)
    pending.push_back(nested);
  while (!pending.empty()) {
    if (!remaining)
      return std::nullopt;
    --remaining;
    auto nested = pending.back();
    pending.pop_back();
    auto result = nested == parameter && parameter != Type::Unknown
                      ? Variance::Covariant
                      : Variance::Bivariant;
    if (nested != parameter && types.isView(nested)) {
      const auto &view = types.view(nested);
      if (occurrence(view.region))
        result = Variance::Covariant;
      auto payload = values.at(view.payload);
      if (view.mode == ParameterMode::Mut && payload != Variance::Bivariant)
        payload = Variance::Invariant;
      result = combine(result, payload);
    } else if (nested != parameter && types.isFunctionPointer(nested)) {
      const auto &contract = types.callable(nested);
      result = combine(values.at(contract.result), values.at(contract.error));
      for (std::size_t i = 0; i < contract.parameters.size(); ++i) {
        auto input = values.at(contract.parameters[i].type);
        if (contract.parameters[i].mode == ParameterMode::Mut &&
            input != Variance::Bivariant)
          input = Variance::Invariant;
        result = combine(result, reverse(input));
        if (i < contract.parameterRegions.size() &&
            occurrence(contract.parameterRegions[i]))
          result = combine(result, Variance::Contravariant);
      }
    } else if (nested != parameter) {
      for (auto child : children(nested))
        result = combine(result, values.at(child));
      if (types.isProduct(nested) && result != Variance::Bivariant &&
          (types.product(nested).kind == AggregateKind::Cell ||
           types.product(nested).kind == AggregateKind::RefCell ||
           types.product(nested).kind == AggregateKind::UnsafeCell))
        result = Variance::Invariant;
      if (types.isErased(nested) &&
          types.erased(nested).bound != RegionId::Unspecified &&
          occurrence(types.erased(nested).bound))
        result = combine(result, Variance::Covariant);
      if (types.isProjection(nested) || types.isErased(nested)) {
        const auto &arguments = types.isProjection(nested)
                                    ? types.parameter(nested).regionArguments
                                    : types.erased(nested).regionArguments;
        if (result != Variance::Bivariant ||
            std::any_of(arguments.begin(), arguments.end(), occurrence))
          result = Variance::Invariant;
      }
    }
    result = combine(values.at(nested), result);
    if (result != values.at(nested)) {
      values[nested] = result;
      for (auto parent : parents[nested])
        pending.push_back(parent);
    }
  }
  return values.at(type);
}
} // namespace mettle
