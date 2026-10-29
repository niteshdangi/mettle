#include "semantics/interfaces.h"
#include "support/limits.h"
#include <functional>

namespace mettle::interfaces {
std::vector<Type> hierarchy(TypeStore &types, const Database &database,
                            Type subject, Type interfaceType, Span span,
                            Diagnostics &diagnostics) {
  std::vector<Type> result{interfaceType};
  std::set<Type> visited{interfaceType};
  for (std::size_t next = 0; next < result.size(); ++next) {
    if (!types.isErased(result[next]))
      continue;
    const auto descriptor = types.erased(result[next]);
    const auto &definition = database.definitions[descriptor.declaration];
    std::vector<TypeBinding> bindings{{definition.self, subject}};
    for (std::size_t p = 0;
         p < definition.parameters.size() && p < descriptor.arguments.size();
         ++p)
      bindings.push_back({definition.parameters[p], descriptor.arguments[p]});
    std::vector<RegionBinding> regions;
    for (std::size_t r = 0;
         r < definition.regions.size() && r < descriptor.regionArguments.size();
         ++r)
      regions.push_back({definition.regions[r], descriptor.regionArguments[r]});
    for (const auto &parent : definition.superinterfaces) {
      if (parent.property != Property::Interface)
        continue;
      auto type = types.substitute(parent.interfaceType, bindings);
      type = types.substituteRegions(type, regions);
      if (visited.insert(type).second)
        result.push_back(type);
    }
    if (result.size() > limits::activeLoans) {
      diagnostics.error("limit", span, "interface hierarchy limit exceeded");
      break;
    }
  }
  return result;
}
std::optional<std::vector<TypeBinding>>
Solver::match(Type pattern, Type actual, bool symmetric,
              RegionEnvironment *regions) {
  std::vector<TypeBinding> bindings;
  auto patternParameters = types.typeParameters(pattern);
  auto variables = patternParameters;
  auto actualParameters = types.typeParameters(actual);
  if (symmetric)
    variables.insert(variables.end(), actualParameters.begin(),
                     actualParameters.end());
  auto variable = [&](Type type) {
    return std::find(variables.begin(), variables.end(), type) !=
               variables.end() &&
           !types.isProjection(type) &&
           (types.isParameter(type) ||
            (types.isConstant(type) &&
             types.parameter(type).kind == TypeParameterKind::Constant));
  };
  std::set<std::pair<Type, Type>> visiting;
  auto proven = [&](RegionAnswer answer) {
    regionInconclusive |= answer == RegionAnswer::Inconclusive;
    return answer == RegionAnswer::Proven;
  };
  std::function<bool(Type, Type)> unify = [&](Type pattern, Type actual) {
    pattern = types.substitute(pattern, bindings);
    actual = types.substitute(actual, bindings);
    if (pattern == actual)
      return true;
    if (!visiting.emplace(pattern, actual).second)
      return false;
    if (variable(pattern)) {
      if (types.isConstant(pattern) != types.isConstant(actual) ||
          (types.isConstant(pattern) && types.parameter(pattern).valueType !=
                                            types.parameter(actual).valueType))
        return false;
      for (const auto &binding : bindings)
        if (binding.parameter == pattern)
          return binding.argument == actual;
      const auto parameters = types.typeParameters(actual);
      if (std::find(parameters.begin(), parameters.end(), pattern) !=
          parameters.end())
        return false;
      bindings.push_back({pattern, actual});
      return true;
    }
    if (symmetric && variable(actual))
      return unify(actual, pattern);
    if (symmetric && types.isConstant(pattern) && types.isConstant(actual) &&
        (types.isSymbolic(pattern) || types.isSymbolic(actual)))
      return true;
    if ((types.isView(pattern) && types.isView(actual)) ||
        (types.isPointer(pattern) && types.isPointer(actual))) {
      auto source = types.view(pattern), target = types.view(actual);
      bool compatible = source.region == target.region || symmetric;
      if (!compatible && regions) {
        RegionSolver solver(types.regions());
        if (types.regions().get(source.region).kind == RegionKind::Inference)
          compatible = proven(
              solver.instantiate(source.region, target.region, *regions));
        else
          compatible =
              proven(solver.outlives(source.region, target.region, *regions)) &&
              proven(solver.outlives(target.region, source.region, *regions));
      }
      return source.mode == target.mode && compatible &&
             unify(source.payload, target.payload);
    }
    if (types.isProduct(pattern) && types.isProduct(actual)) {
      const auto a = types.product(pattern), b = types.product(actual);
      auto origin = [&](Type type) {
        while (types.product(type).regionOrigin != Type::Unknown)
          type = types.product(type).regionOrigin;
        auto generic = types.product(type).genericOrigin;
        return generic == Type::Unknown ? type : generic;
      };
      auto originA = origin(pattern), originB = origin(actual);
      const auto &argumentsA =
          a.genericArguments.empty() ? a.genericParameters : a.genericArguments;
      const auto &argumentsB =
          b.genericArguments.empty() ? b.genericParameters : b.genericArguments;
      if (originA == originB && argumentsA.size() == argumentsB.size()) {
        bool sameRegions = a.regionArguments.size() == b.regionArguments.size();
        auto erased = [](const auto &regions) {
          return std::all_of(regions.begin(), regions.end(), [](auto region) {
            return region == RegionId::Unspecified;
          });
        };
        if (!sameRegions &&
            !(erased(a.regionArguments) && erased(b.regionArguments)))
          return false;
        for (std::size_t i = 0; sameRegions && i < a.regionArguments.size();
             ++i) {
          auto from = a.regionArguments[i], to = b.regionArguments[i];
          if (from == to || symmetric)
            continue;
          if (!regions)
            return false;
          RegionSolver solver(types.regions());
          if (types.regions().get(from).kind == RegionKind::Inference) {
            if (!proven(solver.instantiate(from, to, *regions)))
              return false;
          } else if (!proven(solver.outlives(from, to, *regions)) ||
                     !proven(solver.outlives(to, from, *regions)))
            return false;
        }
        for (std::size_t i = 0; i < argumentsA.size(); ++i)
          if (!unify(argumentsA[i], argumentsB[i]))
            return false;
        return true;
      }
      if (a.kind != AggregateKind::Product &&
          a.kind != AggregateKind::Enumeration &&
          a.kind != AggregateKind::NativeVector &&
          a.kind != AggregateKind::Opaque && a.kind == b.kind &&
          a.components.size() == b.components.size()) {
        if (a.kind == AggregateKind::Array) {
          auto countType = a.arrayCount != Type::Unknown
                               ? types.parameter(a.arrayCount).valueType
                           : b.arrayCount != Type::Unknown
                               ? types.parameter(b.arrayCount).valueType
                               : Type::I32;
          auto left = a.arrayCount == Type::Unknown
                          ? types.constant(countType, a.fields.size())
                          : a.arrayCount;
          auto right = b.arrayCount == Type::Unknown
                           ? types.constant(countType, b.fields.size())
                           : b.arrayCount;
          if (!unify(left, right))
            return false;
        }
        for (std::size_t i = 0; i < a.components.size(); ++i)
          if (!unify(a.components[i], b.components[i]))
            return false;
        return true;
      }
    }
    return false;
  };
  if (!unify(pattern, actual))
    return std::nullopt;
  for (auto parameter : patternParameters)
    if (std::find(actualParameters.begin(), actualParameters.end(),
                  parameter) != actualParameters.end() &&
        std::none_of(bindings.begin(), bindings.end(),
                     [&](const auto &binding) {
                       return binding.parameter == parameter;
                     }))
      bindings.push_back({parameter, parameter});
  return bindings;
}
bool Solver::matchRegions(const ErasedType &provided, const ErasedType &wanted,
                          std::span<const RegionId> quantified,
                          std::span<const RegionRequirement> requirements,
                          std::vector<RegionBinding> &bindings,
                          RegionEnvironment &environment) {
  if (provided.regionArguments.size() != wanted.regionArguments.size())
    return false;
  if (revealOpaque) {
    for (auto parameter : quantified)
      bindings.push_back({parameter, RegionId::Unspecified});
    for (auto parameter : provided.regionParameters)
      bindings.push_back({parameter, RegionId::Unspecified});
    return true;
  }
  auto &store = types.regions();
  if (store.ancestor(environment.universe, wanted.regionUniverse))
    environment.universe = wanted.regionUniverse;
  else if (!store.ancestor(wanted.regionUniverse, environment.universe))
    return false;
  auto scope = store.binder(environment.universe);
  for (auto parameter : quantified)
    if (std::none_of(bindings.begin(), bindings.end(),
                     [&](const auto &binding) {
                       return binding.parameter == parameter;
                     }))
      bindings.push_back({parameter, store.inference(scope)});
  for (auto parameter : provided.regionParameters)
    if (std::none_of(bindings.begin(), bindings.end(),
                     [&](const auto &binding) {
                       return binding.parameter == parameter;
                     }))
      bindings.push_back({parameter, store.inference(scope)});
  RegionSolver solver(store);
  auto proven = [&](RegionAnswer answer) {
    regionInconclusive |= answer == RegionAnswer::Inconclusive;
    return answer == RegionAnswer::Proven;
  };
  for (std::size_t i = 0; i < provided.regionArguments.size(); ++i) {
    auto from = store.substitute(provided.regionArguments[i], bindings);
    auto to = wanted.regionArguments[i];
    if (store.get(from).kind == RegionKind::Inference) {
      if (!proven(solver.instantiate(from, to, environment)))
        return false;
    } else if (!proven(solver.outlives(from, to, environment)) ||
               !proven(solver.outlives(to, from, environment)))
      return false;
  }
  for (auto &binding : bindings)
    for (const auto &substitution : environment.substitutions)
      if (binding.argument == substitution.first)
        binding.argument = substitution.second;
  auto prove = [&](const RegionRequirement &requirement) {
    return proven(solver.outlives(
        store.substitute(requirement.longer, bindings),
        store.substitute(requirement.shorter, bindings), environment));
  };
  for (const auto &requirement : requirements)
    if (!prove(requirement))
      return false;
  for (const auto &requirement : provided.regionRequirements)
    if (!prove(requirement))
      return false;
  for (const auto &requirement : wanted.regionRequirements)
    if (!proven(solver.outlives(requirement.longer, requirement.shorter,
                                environment)))
      return false;
  return proven(solver.leakCheck(environment));
}

bool Solver::prove(const Obligation &obligation, Span span, bool report) {
  if (++steps > limits::activeLoans) {
    regionInconclusive = true;
    if (!limitReported)
      diagnostics.error("limit", span,
                        "interface solver resource limit exceeded");
    limitReported = true;
    return false;
  }
  auto available = assumptions;
  if (types.isProjection(obligation.subject)) {
    auto bounds = projectionBounds(obligation.subject, span);
    available.insert(available.end(), bounds.begin(), bounds.end());
  }
  std::vector<Type> declared;
  if (types.isErased(obligation.subject))
    declared.push_back(obligation.subject);
  if (types.isOpaque(obligation.subject))
    declared = types.product(obligation.subject).opaqueBounds;
  for (auto bound : declared)
    for (auto parent : hierarchy(types, database, obligation.subject, bound,
                                 span, diagnostics))
      available.push_back({obligation.subject, parent});
  for (const auto &assumption : available)
    if (assumption.property == obligation.property) {
      if (assumption.subject != obligation.subject) {
        if (obligation.property != Property::Unpin ||
            !types.isProduct(assumption.subject) ||
            !types.isProduct(obligation.subject))
          continue;
        auto environment = regionEnvironment;
        auto equivalent =
            match(assumption.subject, obligation.subject, false, &environment);
        if (!equivalent || std::any_of(equivalent->begin(), equivalent->end(),
                                       [](auto binding) {
                                         return binding.parameter !=
                                                binding.argument;
                                       }))
          continue;
      }
      if (assumption.interfaceType == obligation.interfaceType)
        return true;
      if (obligation.property == Property::Interface &&
          types.isErased(assumption.interfaceType) &&
          types.isErased(obligation.interfaceType)) {
        const auto provided =
            types.erased(normalize(assumption.interfaceType, {}, span));
        const auto wanted =
            types.erased(normalize(obligation.interfaceType, {}, span));
        auto environment = regionEnvironment;
        std::vector<RegionBinding> bindings;
        if (provided.declaration == wanted.declaration &&
            provided.arguments == wanted.arguments &&
            matchRegions(provided, wanted, {}, {}, bindings, environment)) {
          bool compatible = true;
          for (const auto &required : wanted.associated) {
            auto item =
                std::find_if(provided.associated.begin(),
                             provided.associated.end(), [&](const auto &item) {
                               return item.parameter == required.parameter;
                             });
            compatible &= item != provided.associated.end() &&
                          types.substituteRegions(item->argument, bindings) ==
                              required.argument;
          }
          if (compatible)
            return true;
        }
      }
    }
  if (obligation.property == Property::Copy)
    return types.isCopy(obligation.subject);
  if (obligation.property == Property::Sized)
    return types.isSized(obligation.subject);
  if (obligation.property == Property::Unpin) {
    auto subject = obligation.subject;
    if (types.isUnpin(subject))
      return true;
    if (!provingUnpin.insert(subject).second)
      return false;
    bool valid = false;
    auto normalized = normalize(subject, {}, span);
    if (normalized != subject)
      valid = prove({normalized, Type::Unknown, Property::Unpin}, span, false);
    else if (types.isProduct(subject) && !types.isOpaque(subject)) {
      auto origin = subject;
      while (types.product(origin).regionOrigin != Type::Unknown)
        origin = types.product(origin).regionOrigin;
      if (types.product(origin).genericOrigin != Type::Unknown)
        origin = types.product(origin).genericOrigin;
      auto manual = database.unpinImplementations.find(origin);
      if (manual != database.unpinImplementations.end())
        valid = applicable(manual->second, subject, span, nullptr, true)
                    .has_value();
      else if (types.product(origin).layout.unpin != 0 &&
               types.product(subject).kind != AggregateKind::PhantomPinned) {
        valid = true;
        for (const auto &field : types.product(subject).fields)
          valid &=
              prove({field.type, Type::Unknown, Property::Unpin}, span, false);
      }
    }
    provingUnpin.erase(subject);
    return valid;
  }
  auto selected = implementation(obligation.subject, obligation.interfaceType,
                                 span, report);
  if (selected)
    return true;
  if (regionInconclusive) {
    if (!limitReported)
      diagnostics.error("limit", span,
                        "interface region solving is inconclusive");
    limitReported = true;
    return false;
  }
  if (report)
    diagnostics.error("type", span, "unsatisfied interface obligation");
  return false;
}

std::optional<Type>
Solver::implementedInterface(Type subject, Type interfaceType, Span span) {
  if (!types.isErased(interfaceType))
    return std::nullopt;
  const auto wanted = types.erased(interfaceType);
  std::optional<Type> found;
  for (const auto &candidate : database.implementations) {
    if (!types.isErased(candidate.interfaceType) ||
        types.erased(candidate.interfaceType).declaration != wanted.declaration)
      continue;
    std::vector<RegionBinding> regions;
    auto bindings = applicable(candidate, subject, span, &regions);
    if (!bindings)
      continue;
    auto actual = types.substituteRegions(
        types.substitute(candidate.interfaceType, *bindings), regions);
    auto provided = types.erased(actual);
    auto expected = wanted;
    provided.associated.clear();
    expected.associated.clear();
    bool shape =
        provided.arguments.size() == expected.arguments.size() &&
        provided.regionArguments.size() == expected.regionArguments.size() &&
        provided.regionParameters.size() == expected.regionParameters.size();
    for (std::size_t p = 0; shape && p < provided.arguments.size(); ++p)
      shape = types.eraseRegions(provided.arguments[p]) ==
              types.eraseRegions(expected.arguments[p]);
    if (!shape)
      continue;
    auto result = wanted;
    result.arguments = provided.arguments;
    result.regionArguments = provided.regionArguments;
    const auto &definition = database.definitions[wanted.declaration];
    bool valid = true;
    for (auto &binding : result.associated)
      for (std::size_t item = 0; item < definition.associated.size(); ++item)
        if (definition.associated[item].parameter == binding.parameter) {
          auto value = candidate.associated.find(item);
          if (value == candidate.associated.end() ||
              !value->second.parameters.empty()) {
            valid = false;
            break;
          }
          auto actualValue = types.substituteRegions(
              types.substitute(value->second.value, *bindings), regions);
          if (types.eraseRegions(actualValue) !=
              types.eraseRegions(binding.argument))
            valid = false;
          binding.argument = actualValue;
        }
    if (!valid)
      continue;
    auto bound = types.erasedType(std::move(result));
    if (found && *found != bound) {
      diagnostics.error("type", span,
                        "ambiguous erased interface region contract");
      return std::nullopt;
    }
    found = bound;
  }
  return found;
}

std::vector<Obligation> Solver::projectionBounds(Type projection, Span span) {
  if (!types.isProjection(projection))
    return {};
  const auto descriptor = types.parameter(projection);
  auto subject = descriptor.operands[0], interface = descriptor.operands[1];
  if (!types.isErased(interface) || !prove({subject, interface}, span, false))
    return {};
  const auto owner = types.erased(interface);
  const auto &definition = database.definitions[owner.declaration];
  if (descriptor.value < 0 || static_cast<std::size_t>(descriptor.value) >=
                                  definition.associated.size())
    return {};
  const auto &associated = definition.associated[descriptor.value];
  std::vector<TypeBinding> bindings{{definition.self, subject},
                                    {associated.parameter, projection}};
  for (std::size_t p = 0;
       p < definition.parameters.size() && p < owner.arguments.size(); ++p)
    bindings.push_back({definition.parameters[p], owner.arguments[p]});
  for (std::size_t p = 0;
       p < associated.parameters.size() && p + 2 < descriptor.operands.size();
       ++p)
    bindings.push_back({associated.parameters[p], descriptor.operands[p + 2]});
  auto result = associated.bounds;
  for (auto &bound : result) {
    bound.subject = types.substitute(bound.subject, bindings);
    bound.interfaceType = types.substitute(bound.interfaceType, bindings);
  }
  return result;
}

std::optional<std::pair<const Implementation *, std::vector<TypeBinding>>>
Solver::implementation(Type self, Type interfaceType, Span span, bool report) {
  if (!types.isErased(interfaceType))
    return std::nullopt;
  auto key = std::pair(self, interfaceType);
  if (!active.insert(key).second) {
    regionInconclusive = true;
    return std::nullopt;
  }
  const Implementation *found = nullptr;
  std::vector<TypeBinding> substitutions;
  std::vector<RegionBinding> selectedRegions;
  const auto wanted = types.erased(interfaceType);
  for (const auto &candidate : database.implementations) {
    if (!types.isErased(candidate.interfaceType))
      continue;
    const auto provided = types.erased(candidate.interfaceType);
    if (provided.declaration != wanted.declaration ||
        provided.arguments.size() != wanted.arguments.size())
      continue;
    auto environment = regionEnvironment;
    std::vector<RegionBinding> regions;
    if (!matchRegions(provided, wanted, candidate.regions,
                      candidate.regionRequirements, regions, environment))
      continue;
    auto bindings = match(types.substituteRegions(candidate.target, regions),
                          self, false, &environment);
    if (!bindings)
      continue;
    for (auto &binding : regions)
      for (const auto &substitution : environment.substitutions)
        if (binding.argument == substitution.first)
          binding.argument = substitution.second;
    bool valid = true;
    for (std::size_t i = 0; i < provided.arguments.size(); ++i) {
      auto pattern = types.substituteRegions(
          types.substitute(provided.arguments[i], *bindings), regions);
      auto arguments = match(pattern, wanted.arguments[i], false, &environment);
      if (!arguments) {
        valid = false;
        break;
      }
      for (const auto &binding : *arguments) {
        if (binding.parameter == binding.argument)
          continue;
        if (std::find(candidate.parameters.begin(), candidate.parameters.end(),
                      binding.parameter) == candidate.parameters.end()) {
          valid = false;
          break;
        }
        bindings->push_back(binding);
      }
    }
    if (!valid)
      continue;
    auto savedEnvironment = regionEnvironment;
    regionEnvironment = environment;
    valid = constraints(candidate, *bindings, span, regions);
    regionEnvironment = std::move(savedEnvironment);
    if (!valid)
      continue;
    const auto &definition = database.definitions[wanted.declaration];
    auto parents = *bindings;
    auto parentRegions = regions;
    for (std::size_t i = 0;
         i < definition.regions.size() && i < wanted.regionArguments.size();
         ++i)
      parentRegions.push_back(
          {definition.regions[i], wanted.regionArguments[i]});
    parents.push_back({definition.self, self});
    for (std::size_t i = 0;
         i < definition.parameters.size() && i < wanted.arguments.size(); ++i)
      parents.push_back({definition.parameters[i], wanted.arguments[i]});
    for (auto parent : definition.superinterfaces) {
      parent.subject = types.substitute(parent.subject, parents);
      parent.interfaceType = types.substitute(parent.interfaceType, parents);
      parent.subject = types.substituteRegions(parent.subject, parentRegions);
      parent.interfaceType =
          types.substituteRegions(parent.interfaceType, parentRegions);
      if (!prove(parent, span, false)) {
        valid = false;
        break;
      }
    }
    if (!valid)
      continue;
    for (const auto &binding : wanted.associated) {
      auto index = std::find_if(
          database.definitions[wanted.declaration].associated.begin(),
          database.definitions[wanted.declaration].associated.end(),
          [&](const auto &associated) {
            return associated.parameter == binding.parameter;
          });
      if (index == database.definitions[wanted.declaration].associated.end()) {
        valid = false;
        break;
      }
      auto ordinal = static_cast<std::size_t>(
          index - database.definitions[wanted.declaration].associated.begin());
      auto value = candidate.associated.find(ordinal);
      if (value == candidate.associated.end() ||
          normalize(types.substituteRegions(value->second.value, regions),
                    *bindings, span) != binding.argument) {
        valid = false;
        break;
      }
    }
    if (!valid)
      continue;
    if (found) {
      active.erase(key);
      if (report)
        diagnostics.error("type", span, "ambiguous interface implementation");
      return std::nullopt;
    }
    found = &candidate;
    substitutions = std::move(*bindings);
    selectedRegions = std::move(regions);
  }
  active.erase(key);
  if (!found)
    return std::nullopt;
  regionSelections[key] = std::move(selectedRegions);
  return std::pair(found, std::move(substitutions));
}

Type Solver::normalize(Type type, std::span<const TypeBinding> bindings,
                       Span span) {
  type = types.substitute(type, bindings);
  type = types.substitute(type, contextualEqualities);
  if (types.isErased(type)) {
    if (!normalizing.insert(type).second)
      return type;
    const auto descriptor = types.erased(type);
    std::vector<TypeBinding> rebased;
    for (auto argument : descriptor.arguments) {
      auto normalized = normalize(argument, {}, span);
      if (normalized != argument)
        rebased.push_back({argument, normalized});
    }
    for (auto associated : descriptor.associated) {
      auto normalized = normalize(associated.argument, {}, span);
      if (normalized != associated.argument)
        rebased.push_back({associated.argument, normalized});
    }
    normalizing.erase(type);
    return rebased.empty() ? type : types.substitute(type, rebased);
  }
  std::optional<Projection> request;
  if (types.isProjection(type)) {
    const auto descriptor = types.parameter(type);
    request =
        Projection{type,
                   descriptor.operands[0],
                   descriptor.operands[1],
                   static_cast<std::size_t>(descriptor.value),
                   {descriptor.operands.begin() + 2, descriptor.operands.end()},
                   descriptor.regionArguments};
  } else {
    auto projection = std::find_if(
        database.projections.begin(), database.projections.end(),
        [&](const auto &projection) { return projection.parameter == type; });
    if (projection != database.projections.end())
      request = *projection;
  }
  if (request) {
    const auto *projection = &*request;
    if (!normalizing.insert(type).second) {
      diagnostics.error("type", span, "cyclic associated projection");
      return Type::Unknown;
    }
    auto subject = normalize(projection->subject, bindings, span);
    auto interfaceType = types.substitute(projection->interfaceType, bindings);
    const auto &definition =
        database.definitions[types.erased(interfaceType).declaration];
    if (projection->associated >= definition.associated.size()) {
      normalizing.erase(type);
      diagnostics.error("internal", span,
                        "invalid associated projection identity");
      return Type::Unknown;
    }
    for (const auto &associated : types.erased(interfaceType).associated)
      if (associated.parameter ==
          definition.associated[projection->associated].parameter) {
        auto result = normalize(associated.argument, bindings, span);
        normalizing.erase(type);
        return result;
      }
    if (types.isErased(subject))
      for (const auto &associated : types.erased(subject).associated)
        if (associated.parameter ==
            definition.associated[projection->associated].parameter) {
          auto result = normalize(associated.argument, bindings, span);
          normalizing.erase(type);
          return result;
        }
    if (types.isErased(subject))
      for (auto bound :
           hierarchy(types, database, subject, subject, span, diagnostics)) {
        const auto descriptor = types.erased(bound);
        if (descriptor.declaration != types.erased(interfaceType).declaration)
          continue;
        for (const auto &associated : descriptor.associated)
          if (associated.parameter ==
              definition.associated[projection->associated].parameter) {
            auto result = normalize(associated.argument, bindings, span);
            normalizing.erase(type);
            return result;
          }
      }
    if (types.isOpaque(subject)) {
      const auto declared = types.product(subject).opaqueBounds;
      std::vector<Type> bounds;
      for (auto bound : declared) {
        auto inherited =
            hierarchy(types, database, subject, bound, span, diagnostics);
        bounds.insert(bounds.end(), inherited.begin(), inherited.end());
      }
      for (auto bound : bounds) {
        const auto descriptor = types.erased(bound);
        if (descriptor.declaration != types.erased(interfaceType).declaration)
          continue;
        for (const auto &associated : descriptor.associated)
          if (associated.parameter ==
              definition.associated[projection->associated].parameter) {
            auto result = normalize(associated.argument, bindings, span);
            normalizing.erase(type);
            return result;
          }
      }
    }
    for (const auto &assumption : assumptions) {
      if (assumption.property != Property::Interface ||
          assumption.subject != subject ||
          !types.isErased(assumption.interfaceType))
        continue;
      const auto descriptor = types.erased(assumption.interfaceType);
      if (descriptor.declaration != types.erased(interfaceType).declaration ||
          descriptor.arguments != types.erased(interfaceType).arguments)
        continue;
      for (const auto &associated : descriptor.associated)
        if (associated.parameter ==
            definition.associated[projection->associated].parameter) {
          auto result = normalize(associated.argument, bindings, span);
          normalizing.erase(type);
          return result;
        }
    }
    if (types.isOpaque(subject) && (revealOpaque || types.isConstant(type))) {
      auto hidden = types.product(subject).fields[0].type;
      if (hidden != Type::Unknown) {
        std::vector<TypeBinding> reveal{{subject, hidden}};
        auto interface = types.substitute(interfaceType, reveal);
        std::vector<Type> arguments;
        for (auto argument : projection->arguments)
          arguments.push_back(types.substitute(argument, reveal));
        auto source = types.parameter(type);
        auto represented = types.projection(
            hidden, interface, projection->associated, std::move(arguments),
            source.valueType, source.copyRequested, source.sized,
            source.regionArguments);
        auto result = normalize(represented, bindings, span);
        normalizing.erase(type);
        return result;
      }
    }
    auto selected = implementation(subject, interfaceType, span, false);
    if (!selected) {
      normalizing.erase(type);
      if (regionInconclusive) {
        if (!limitReported)
          diagnostics.error("limit", span,
                            "associated region solving is inconclusive");
        limitReported = true;
        return Type::Unknown;
      }
      return type;
    }
    auto found = selected->first->associated.find(projection->associated);
    if (found == selected->first->associated.end()) {
      normalizing.erase(type);
      diagnostics.error("type", span, "associated item has no implementation");
      return Type::Unknown;
    }
    auto substitutions = selected->second;
    if (found->second.parameters.size() != projection->arguments.size()) {
      normalizing.erase(type);
      diagnostics.error("type", span,
                        "associated family argument count does not match");
      return Type::Unknown;
    }
    if (found->second.regions.size() != projection->regionArguments.size()) {
      normalizing.erase(type);
      diagnostics.error(
          "type", span,
          "associated family region argument count does not match");
      return Type::Unknown;
    }
    for (std::size_t i = 0; i < projection->arguments.size(); ++i)
      substitutions.push_back(
          {found->second.parameters[i],
           normalize(projection->arguments[i], bindings, span)});
    auto regions = regionSelections[{subject, interfaceType}];
    const auto &interface = types.erased(interfaceType);
    for (std::size_t i = 0;
         i < definition.regions.size() && i < interface.regionArguments.size();
         ++i)
      regions.push_back({definition.regions[i], interface.regionArguments[i]});
    for (std::size_t i = 0; i < projection->regionArguments.size(); ++i)
      regions.push_back(
          {found->second.regions[i], projection->regionArguments[i]});
    auto environment = regionEnvironment;
    for (auto region : projection->regionArguments) {
      auto universe = types.regions().get(region).universe;
      if (types.regions().ancestor(environment.universe, universe))
        environment.universe = universe;
      else if (!types.regions().ancestor(universe, environment.universe)) {
        normalizing.erase(type);
        diagnostics.error("region", span,
                          "associated family region escapes its binder");
        return Type::Unknown;
      }
    }
    RegionSolver solver(types.regions());
    for (const auto &requirement : found->second.regionRequirements) {
      auto answer = solver.outlives(
          types.regions().substitute(requirement.longer, regions),
          types.regions().substitute(requirement.shorter, regions),
          environment);
      if (answer != RegionAnswer::Proven) {
        normalizing.erase(type);
        diagnostics.error(
            answer == RegionAnswer::Inconclusive ? "limit" : "region", span,
            "associated family outlives obligation is not proven");
        return Type::Unknown;
      }
    }
    auto result =
        normalize(types.substituteRegions(found->second.value, regions),
                  substitutions, span);
    normalizing.erase(type);
    return result;
  }
  if (types.isView(type)) {
    const auto view = types.view(type);
    auto payload = normalize(view.payload, bindings, span);
    return types.viewType(payload, view.mode, view.region);
  }
  if (types.isPointer(type)) {
    auto pointer = types.pointer(type);
    return types.pointerType(normalize(pointer.payload, bindings, span),
                             pointer.mode);
  }
  if (types.isSlice(type)) {
    auto element = types.slice(type).element;
    return types.sliceType(normalize(element, {}, span));
  }
  if (types.isFunctionPointer(type)) {
    if (!normalizing.insert(type).second)
      return type;
    auto signature = types.callable(type);
    for (auto &parameter : signature.parameters)
      parameter.type = normalize(parameter.type, {}, span);
    signature.result = normalize(signature.result, {}, span);
    signature.abiResult = normalize(signature.abiResult, {}, span);
    if (signature.error != Type::Unknown)
      signature.error = normalize(signature.error, {}, span);
    normalizing.erase(type);
    return types.callableType(std::move(signature));
  }
  if (types.isProduct(type)) {
    const auto product = types.product(type);
    if (revealOpaque && product.genericOrigin != Type::Unknown) {
      auto arguments = product.genericArguments;
      bool changed = false;
      for (auto &argument : arguments) {
        auto represented = normalize(argument, {}, span);
        changed |= represented != argument;
        argument = represented;
      }
      if (changed)
        return normalize(types.instantiateProduct(product.genericOrigin,
                                                  std::move(arguments)),
                         {}, span);
    }
    if (!product.components.empty() && product.kind != AggregateKind::Product &&
        product.kind != AggregateKind::Enumeration &&
        product.kind != AggregateKind::Opaque) {
      std::vector<Type> components;
      for (auto component : product.components)
        components.push_back(normalize(component, bindings, span));
      if (product.kind == AggregateKind::Array &&
          product.arrayCount != Type::Unknown)
        return types.arrayType(components[0],
                               normalize(product.arrayCount, bindings, span));
      return types.structural(
          product.kind, std::move(components),
          static_cast<std::uint32_t>(product.fields.size()));
    }
    if (normalizing.insert(type).second) {
      auto fields = product.fields;
      bool changed = false;
      for (auto &field : fields) {
        auto normalized = normalize(field.type, bindings, span);
        changed |= normalized != field.type;
        field.type = normalized;
      }
      if (changed)
        types.defineProduct(type, std::move(fields));
      normalizing.erase(type);
    }
  }
  return type;
}

std::optional<Selection> Solver::method(Type self, Type interfaceType,
                                        std::size_t slot,
                                        std::span<const Type> arguments,
                                        Span span) {
  auto selected = implementation(self, interfaceType, span, true);
  if (!selected) {
    if (regionInconclusive) {
      if (!limitReported)
        diagnostics.error("limit", span,
                          "interface method region solving is inconclusive");
      limitReported = true;
    } else
      diagnostics.error("type", span,
                        "no applicable interface method implementation");
    return std::nullopt;
  }
  auto found = selected->first->methods.find(slot);
  if (found == selected->first->methods.end()) {
    diagnostics.error("type", span, "interface method is not implemented");
    return std::nullopt;
  }
  Selection result{found->second.function, {}};
  for (auto argument : found->second.arguments)
    result.arguments.push_back(normalize(argument, selected->second, span));
  result.arguments.insert(result.arguments.end(), arguments.begin(),
                          arguments.end());
  return result;
}

} // namespace mettle::interfaces
