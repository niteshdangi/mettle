#include "semantics/interfaces.h"
#include "support/limits.h"
#include <functional>

namespace mettle::interfaces {
namespace {
bool structuralAggregate(AggregateKind kind) {
  return kind != AggregateKind::Product && kind != AggregateKind::Enumeration &&
         kind != AggregateKind::NativeVector && kind != AggregateKind::Opaque;
}
Type nominalOrigin(const TypeStore &types, Type type) {
  while (types.product(type).regionOrigin != Type::Unknown)
    type = types.product(type).regionOrigin;
  auto generic = types.product(type).genericOrigin;
  return generic == Type::Unknown ? type : generic;
}
} // namespace
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
  if (types.isProduct(pattern) && types.isProduct(actual) &&
      !structuralAggregate(types.product(pattern).kind) &&
      nominalOrigin(types, pattern) != nominalOrigin(types, actual))
    return std::nullopt;
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
    struct MatchScope {
      std::set<std::pair<Type, Type>> &visiting;
      std::pair<Type, Type> key;
      ~MatchScope() { visiting.erase(key); }
    } scope{visiting, {pattern, actual}};
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
    if (types.isSlice(pattern) && types.isSlice(actual))
      return unify(types.slice(pattern).element, types.slice(actual).element);
    if (types.isProduct(pattern) && types.isProduct(actual)) {
      auto originA = nominalOrigin(types, pattern),
           originB = nominalOrigin(types, actual);
      auto structural = structuralAggregate;
      // Distinct nominal types can never unify; skip copying their layouts.
      if (originA != originB && !structural(types.product(pattern).kind))
        return false;
      // The recursion below may intern types, so keep only the parts read.
      struct Shape {
        AggregateKind kind;
        std::vector<Type> arguments, components;
        std::vector<RegionId> regionArguments;
        Type arrayCount;
        std::size_t fieldCount;
      };
      auto shape = [&](Type type) {
        const auto &record = types.product(type);
        return Shape{record.kind,
                     record.genericArguments.empty() ? record.genericParameters
                                                     : record.genericArguments,
                     record.components,
                     record.regionArguments,
                     record.arrayCount,
                     record.fields.size()};
      };
      const auto a = shape(pattern), b = shape(actual);
      const auto &argumentsA = a.arguments;
      const auto &argumentsB = b.arguments;
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
      if (structural(a.kind) && a.kind == b.kind &&
          a.components.size() == b.components.size()) {
        if (a.kind == AggregateKind::Array) {
          auto countType = a.arrayCount != Type::Unknown
                               ? types.parameter(a.arrayCount).valueType
                           : b.arrayCount != Type::Unknown
                               ? types.parameter(b.arrayCount).valueType
                               : Type::I32;
          auto left = a.arrayCount == Type::Unknown
                          ? types.constant(countType, a.fieldCount)
                          : a.arrayCount;
          auto right = b.arrayCount == Type::Unknown
                           ? types.constant(countType, b.fieldCount)
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
            if (item == provided.associated.end()) {
              // An unbound associated type is still equal to its wanted value
              // when the subject's projection normalizes to it.
              compatible &=
                  projectedBinding(obligation.subject, wanted, required, span);
              continue;
            }
            auto value = types.substituteRegions(item->argument, bindings);
            // Generic bounds are checked with erased regions, so an erased
            // binding stands for the same value at any region.
            auto erased = [&](Type type) {
              return types.eraseRegions(type) == type;
            };
            compatible &= value == required.argument ||
                          ((erased(value) || erased(required.argument)) &&
                           types.eraseRegions(value) ==
                               types.eraseRegions(required.argument));
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
  if (obligation.property == Property::Transferable ||
      obligation.property == Property::Shareable ||
      obligation.property == Property::Static)
    return proveConcurrency(obligation.property, obligation.subject, span);
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
  if (report) {
    const std::array<Type, 2> namesInMessage{obligation.subject,
                                             obligation.interfaceType};
    const auto subject = displayType(types, obligation.subject, namesInMessage);
    const auto interface =
        displayType(types, obligation.interfaceType, namesInMessage);
    diagnostics.error(
        "type", span,
        "unsatisfied interface obligation: no implementation of '" + interface +
            "' is available for '" + subject + "'",
        {{"help",
          {},
          "add `extend " + subject + " implements " + interface +
              " { ... }`"}});
  }
  return false;
}

// Structural derivation of Transferable/Shareable/Static. Raw pointers and
// foreign-affine types opt out unless an `unsafe extend` opts them back in.
bool Solver::proveConcurrency(Property property, Type subject, Span span) {
  const auto key = std::make_pair(property, subject);
  if (!provingConcurrency.insert(key).second)
    return true;
  auto finish = [&](bool result) {
    provingConcurrency.erase(key);
    return result;
  };
  auto sub = [&](Property nested, Type type) {
    return prove({type, Type::Unknown, nested}, span, false);
  };
  auto all = [&](const std::vector<TypeField> &fields) {
    for (const auto &field : fields)
      if (!sub(property, field.type))
        return false;
    return true;
  };
  const bool isStatic = property == Property::Static;
  auto normalized = normalize(subject, {}, span);
  if (normalized != subject)
    return finish(sub(property, normalized));
  if (types.isParameter(subject) || types.isProjection(subject))
    return finish(false);
  if (types.isConstant(subject))
    return finish(true);
  if (types.isPointer(subject))
    return finish(isStatic);
  if (types.isFunctionPointer(subject))
    return finish(true);
  if (types.isSlice(subject))
    return finish(sub(property, types.slice(subject).element));
  if (types.isView(subject)) {
    const auto &view = types.view(subject);
    if (isStatic)
      return finish(view.region == RegionId::Static &&
                    sub(property, view.payload));
    // A read view crosses threads only when its payload may be shared; an
    // exclusive view carries the payload's own transfer property.
    auto payload =
        view.mode == ParameterMode::Mut ? property : Property::Shareable;
    return finish(sub(payload, view.payload));
  }
  if (types.isErased(subject)) {
    std::set<std::size_t> seen;
    std::vector<std::size_t> pending{types.erased(subject).declaration};
    while (!pending.empty()) {
      auto index = pending.back();
      pending.pop_back();
      if (!seen.insert(index).second)
        continue;
      for (const auto &parent : database.definitions[index].superinterfaces) {
        if (parent.property == property)
          return finish(true);
        if (parent.property == Property::Interface &&
            types.isErased(parent.interfaceType))
          pending.push_back(types.erased(parent.interfaceType).declaration);
      }
    }
    return finish(false);
  }
  if (!types.isProduct(subject))
    return finish(true);
  const auto &record = types.product(subject);
  if (isStatic) {
    for (auto region : record.regionArguments)
      if (region != RegionId::Static)
        return finish(false);
    if (record.kind == AggregateKind::Array ||
        record.kind == AggregateKind::Coroutine) {
      auto components = record.components;
      for (auto component : components)
        if (!sub(property, component))
          return finish(false);
    }
    return finish(all(types.product(subject).fields));
  }
  auto origin = subject;
  while (types.product(origin).regionOrigin != Type::Unknown)
    origin = types.product(origin).regionOrigin;
  if (types.product(origin).genericOrigin != Type::Unknown)
    origin = types.product(origin).genericOrigin;
  auto manual = database.concurrencyDeclarations.find({property, origin});
  if (manual != database.concurrencyDeclarations.end())
    return finish(
        !manual->second.negative &&
        applicable(manual->second.implementation, subject, span, nullptr, true)
            .has_value());
  switch (record.kind) {
  case AggregateKind::Atomic:
    return finish(true);
  case AggregateKind::Ref:
  case AggregateKind::RefMut:
  case AggregateKind::VarArgs:
    return finish(false);
  case AggregateKind::Cell:
  case AggregateKind::RefCell:
  case AggregateKind::UnsafeCell:
    return finish(property == Property::Transferable && all(record.fields));
  case AggregateKind::Array:
    if (!record.components.empty() && !sub(property, record.components[0]))
      return finish(false);
    break;
  case AggregateKind::Coroutine: {
    // The output, the closure's captures and what the body holds across a
    // suspension. Copied first: deriving the interior may add types.
    auto components = record.components;
    for (auto component : components)
      if (!sub(property, component))
        return finish(false);
    if (components.size() > 1)
      for (auto held : types.coroutineInterior(components[1]))
        if (!sub(property, held))
          return finish(false);
    return finish(true);
  }
  default:
    break;
  }
  return finish(all(record.fields));
}

bool Solver::projectedBinding(Type subject, const ErasedType &wanted,
                              const TypeBinding &required, Span span) {
  const auto &definition = database.definitions[wanted.declaration];
  auto item = std::find_if(
      definition.associated.begin(), definition.associated.end(),
      [&](const auto &item) { return item.parameter == required.parameter; });
  if (item == definition.associated.end() || !item->parameters.empty() ||
      !item->regions.empty() || item->constant)
    return false;
  auto bare = wanted;
  bare.associated.clear();
  auto projection = types.projection(
      subject, types.erasedType(std::move(bare)),
      static_cast<std::size_t>(item - definition.associated.begin()));
  auto actual = normalize(projection, {}, span);
  return actual == normalize(required.argument, {}, span);
}

const std::vector<std::size_t> &
Solver::candidatesFor(std::uint32_t declaration) {
  auto &index = database.implementationsByDeclaration;
  for (auto &i = database.indexedImplementations;
       i < database.implementations.size(); ++i) {
    auto interfaceType = database.implementations[i].interfaceType;
    if (!types.isErased(interfaceType))
      continue;
    auto owner = types.erased(interfaceType).declaration;
    if (index.size() <= owner)
      index.resize(owner + 1);
    index[owner].push_back(i);
  }
  static const std::vector<std::size_t> none;
  return declaration < index.size() ? index[declaration] : none;
}

std::optional<Type>
Solver::implementedInterface(Type subject, Type interfaceType, Span span) {
  if (!types.isErased(interfaceType))
    return std::nullopt;
  const auto wanted = types.erased(interfaceType);
  std::optional<Type> found;
  for (auto position : candidatesFor(wanted.declaration)) {
    const auto &candidate = database.implementations[position];
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
          auto actualValue = normalize(
              types.substituteRegions(
                  types.substitute(value->second.value, *bindings), regions),
              {}, span);
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
  std::vector<RegionBinding> regions;
  for (std::size_t r = 0;
       r < associated.regions.size() && r < descriptor.regionArguments.size();
       ++r)
    regions.push_back({associated.regions[r], descriptor.regionArguments[r]});
  auto result = associated.bounds;
  for (auto &bound : result) {
    bound.subject = types.substitute(bound.subject, bindings);
    bound.interfaceType = types.substitute(bound.interfaceType, bindings);
    bound.interfaceType = types.substituteRegions(bound.interfaceType, regions);
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
  for (auto position : candidatesFor(wanted.declaration)) {
    const auto &candidate = database.implementations[position];
    if (types.erased(candidate.interfaceType).arguments.size() !=
        wanted.arguments.size())
      continue;
    auto provided = types.erased(candidate.interfaceType);
    auto requirements = candidate.regionRequirements;
    requirements.insert(requirements.end(), provided.regionRequirements.begin(),
                        provided.regionRequirements.end());
    provided.regionRequirements.clear();
    auto environment = regionEnvironment;
    std::vector<RegionBinding> regions;
    if (!matchRegions(provided, wanted, candidate.regions, {}, regions,
                      environment))
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
      auto argument = wanted.arguments[i];
      if (revealOpaque) {
        pattern = types.eraseRegions(pattern);
        argument = types.eraseRegions(argument);
      }
      auto arguments = match(pattern, argument, false, &environment);
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
      if (value == candidate.associated.end()) {
        valid = false;
        break;
      }
      auto have =
          normalize(types.substituteRegions(value->second.value, regions),
                    *bindings, span);
      auto want = normalize(binding.argument, {}, span);
      // Selection at instantiation time ignores regions.
      if (have != want && !(revealOpaque && types.eraseRegions(have) ==
                                                types.eraseRegions(want))) {
        // Equal up to the regions the candidate leaves to be inferred; those
        // may be instantiated with the wanted type's (inner) regions.
        std::function<void(Type)> widen = [&](Type type) {
          if (types.isView(type)) {
            auto universe =
                types.regions().get(types.view(type).region).universe;
            if (types.regions().ancestor(environment.universe, universe))
              environment.universe = universe;
            widen(types.view(type).payload);
          } else if (types.isProduct(type)) {
            for (auto component : types.product(type).components)
              widen(component);
            for (auto argument : types.product(type).genericArguments)
              widen(argument);
          }
        };
        widen(want);
        auto compared = match(have, want, false, &environment);
        if (!compared ||
            std::any_of(compared->begin(), compared->end(), [](auto item) {
              return item.parameter != item.argument;
            })) {
          valid = false;
          break;
        }
      }
    }
    for (auto &binding : regions)
      for (const auto &substitution : environment.substitutions)
        if (binding.argument == substitution.first)
          binding.argument = substitution.second;
    if (!revealOpaque) {
      RegionSolver solver(types.regions());
      for (const auto &requirement : requirements) {
        auto answer = solver.outlives(
            types.regions().substitute(requirement.longer, regions),
            types.regions().substitute(requirement.shorter, regions),
            environment);
        regionInconclusive |= answer == RegionAnswer::Inconclusive;
        valid &= answer == RegionAnswer::Proven;
      }
      auto answer = solver.leakCheck(environment);
      regionInconclusive |= answer == RegionAnswer::Inconclusive;
      valid &= answer == RegionAnswer::Proven;
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
  if (!normalizationDepth)
    normalizationSteps = 0;
  if (++normalizationSteps > limits::activeLoans ||
      normalizationDepth >= limits::typeDepth)
    throw std::length_error("generic normalization resource limit exceeded");
  struct Scope {
    unsigned &depth;
    explicit Scope(unsigned &depth) : depth(depth) { ++depth; }
    ~Scope() { --depth; }
  } scope(normalizationDepth);
  type = types.substitute(type, bindings);
  bindings = {};
  type = types.substitute(type, contextualEqualities);
  if (types.isProduct(type) && !types.isSymbolic(type))
    return type;
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
    // A family projection carries the associated-type bounds declared on the
    // family, instantiated at the projection's region arguments.
    if (types.isProjection(subject))
      for (const auto &bound : projectionBounds(subject, span)) {
        if (bound.property != Property::Interface || bound.subject != subject)
          continue;
        for (auto parent : hierarchy(types, database, subject,
                                     bound.interfaceType, span, diagnostics)) {
          const auto descriptor = types.erased(parent);
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
    auto associatedValue = found->second.value;
    if (associatedValue == Type::Unknown && found->second.fromDefault) {
      associatedValue =
          definition.associated[projection->associated].defaultValue;
      auto bindDefault = [&](Type parameter, Type argument) {
        if (std::none_of(substitutions.begin(), substitutions.end(),
                         [&](const auto &binding) {
                           return binding.parameter == parameter;
                         }))
          substitutions.push_back({parameter, argument});
      };
      bindDefault(definition.self, subject);
      for (std::size_t p = 0;
           p < definition.parameters.size() && p < interface.arguments.size();
           ++p)
        bindDefault(definition.parameters[p], interface.arguments[p]);
    }
    if (associatedValue == Type::Unknown) {
      normalizing.erase(type);
      return type;
    }
    auto result = normalize(types.substituteRegions(associatedValue, regions),
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
    if (product.genericOrigin != Type::Unknown) {
      auto arguments = product.genericArguments;
      bool changed = false;
      for (auto &argument : arguments) {
        auto represented = normalize(argument, {}, span);
        changed |= represented != argument;
        argument = represented;
      }
      if (changed) {
        auto instance =
            types.instantiateProduct(product.genericOrigin, arguments);
        if (product.regionOrigin != Type::Unknown) {
          if (!normalizing.insert(type).second)
            return type;
          struct Scope {
            std::set<Type> &active;
            Type type;
            ~Scope() { active.erase(type); }
          } scope{normalizing, type};
          auto fields = product.fields;
          for (auto &field : fields)
            field.type = normalize(field.type, {}, span);
          auto shell =
              types.regionalShell(instance, product.regionArguments,
                                  std::move(arguments), product.regionPattern);
          instance = types.regionalProduct(shell, std::move(fields),
                                           product.regionArguments, true);
        }
        return revealOpaque ? normalize(instance, {}, span) : instance;
      }
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
      normalizing.erase(type);
      if (changed)
        return types.regionalProduct(type, std::move(fields),
                                     product.regionArguments, true);
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
