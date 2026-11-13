#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include <algorithm>
#include <functional>

namespace mettle {
void Checker::interfaceHeaders() {
  if (module.interfaces.size() > limits::interfaces) {
    error("limit", {}, "interface declaration limit exceeded");
    return;
  }
  auto &database = *checked.interfaceData;
  database.definitions.resize(module.interfaces.size());
  std::size_t declarationIndex = 0;
  for (const auto &syntax : module.interfaces) {
    auto name = definitionName(syntax.span, syntax.name);
    const auto index = declarationIndex++;
    if (!interfaceNames.emplace(name, index).second) {
      error("name", syntax.span,
            "duplicate interface '" + displayPath(syntax.name) + "'");
      continue;
    }
    if (imported(syntax.span))
      continue;
    interfaces::Definition definition;
    definition.name = name;
    definition.span = syntax.span;
    definition.package =
        checked.namespaces().packageOf(syntax.span).value_or(unknownPackage);
    definition.unsafeInterface = syntax.unsafeInterface;
    definition.self =
        checked.types->declareParameter(name + ".Self", false, false);
    database.definitions[index] = std::move(definition);
  }
  if (!diagnostics.empty())
    return;
  for (std::size_t index = 0; index < module.interfaces.size(); ++index) {
    const auto &syntax = module.interfaces[index];
    if (imported(syntax.span))
      continue;
    auto &definition = database.definitions[index];
    const auto &name = definition.name;
    for (const auto &associated : syntax.associated) {
      interfaces::Associated item;
      item.name = associated.name;
      item.constant = associated.constant;
      item.asyncFuture = associated.asyncFuture;
      item.asyncFutureDefaultInferred = associated.asyncFutureDefaultInferred;
      item.parameter =
          associated.constant
              ? checked.types->declareConstParameter(
                    name + "::" + associated.name, Type::I32)
              : checked.types->declareParameter(
                    name + "::" + associated.name,
                    std::any_of(associated.bounds.begin(),
                                associated.bounds.end(),
                                [&](const auto &bound) {
                                  return interfaceProperty(bound, "Copy",
                                                           associated.span);
                                }),
                    !std::any_of(associated.bounds.begin(),
                                 associated.bounds.end(),
                                 [](const auto &bound) {
                                   return bound.name == "unsized";
                                 }));
      if (std::any_of(
              definition.associated.begin(), definition.associated.end(),
              [&](const auto &prior) { return prior.name == item.name; }))
        error("name", associated.span, "duplicate associated item");
      if (!associated.constant &&
          std::any_of(associated.bounds.begin(), associated.bounds.end(),
                      [&](const auto &bound) {
                        return interfaceProperty(bound, "Unpin",
                                                 associated.span);
                      }))
        checked.types->constrainUnpin(item.parameter);
      definition.associated.push_back(std::move(item));
    }
  }
}

bool Checker::intrinsicProperty(const TypeSyntax &bound,
                                std::string_view property, Span span) const {
  return bound.form == TypeForm::Named &&
         (bound.name == property ||
          ((property == "Unpin" || property == "Transferable" ||
            property == "Shareable" || property == "Static") &&
           bound.name == "core::marker::" + std::string(property))) &&
         bound.arguments.empty() &&
         !checked.namespaces().lookup(nameModule(span, bound.context),
                                      bound.name, resolution::Namespace::Type,
                                      span);
}

std::optional<interfaces::Property>
Checker::propertyBound(const TypeSyntax &bound, Span span) const {
  using interfaces::Property;
  for (auto [name, property] : {std::pair{"Copy", Property::Copy},
                                {"Sized", Property::Sized},
                                {"Unpin", Property::Unpin},
                                {"Transferable", Property::Transferable},
                                {"Shareable", Property::Shareable},
                                {"Static", Property::Static}})
    if (intrinsicProperty(bound, name, span))
      return property;
  return std::nullopt;
}

bool Checker::interfaceProperty(const TypeSyntax &bound,
                                std::string_view property, Span span) {
  std::set<std::size_t> active;
  std::function<bool(const TypeSyntax &, Span)> visit =
      [&](const TypeSyntax &current, Span context) {
        if (intrinsicProperty(current, property, context))
          return true;
        auto canonical = typeName(current.name, context, {}, current.context);
        auto found = interfaceNames.find(canonical);
        if (found == interfaceNames.end() ||
            !active.insert(found->second).second)
          return false;
        const auto &declaration = module.interfaces[found->second];
        for (const auto &parent : declaration.superinterfaces)
          if (visit(parent, declaration.span))
            return true;
        for (const auto &constraint : declaration.constraints)
          if (constraint.subject.name == "Self")
            for (const auto &bound : constraint.bounds)
              if (visit(bound, declaration.span))
                return true;
        return false;
      };
  return visit(bound, span);
}

Type Checker::interfaceBound(const TypeSyntax &bound, Span span,
                             std::string_view owner, Type subject) {
  if (interfaceDepth >= limits::typeDepth) {
    error("limit", span, "interface bound expansion limit exceeded");
    return Type::Unknown;
  }
  ++interfaceDepth;
  struct Depth {
    unsigned &value;
    ~Depth() { --value; }
  } depth{interfaceDepth};
  auto canonical = typeName(bound.name, span, owner, bound.context);
  auto found = interfaceNames.find(canonical);
  if (found == interfaceNames.end()) {
    error("type", span,
          "unknown interface bound '" + displayPath(bound.name) + "'");
    return Type::Unknown;
  }
  const auto &syntax = module.interfaces[found->second];
  auto &definition = checked.interfaceData->definitions[found->second];
  ErasedType result{definition.name, static_cast<std::uint32_t>(found->second)};
  if (!bound.binders.empty()) {
    std::vector<GenericParameter> parameters;
    for (const auto &name : bound.binders) {
      GenericParameter parameter;
      parameter.kind = GenericParameterKind::Region;
      parameter.name = name.spelling;
      parameter.span = name.span;
      parameter.nameSpan = name.span;
      parameter.context = name.context;
      parameters.push_back(std::move(parameter));
    }
    result.regionParameters = pushRegionParameters(parameters, span);
  }
  result.regionUniverse = regionEnvironment().universe;
  std::size_t supplied = 0;
  for (const auto &argument : bound.arguments) {
    if (!argument.region.empty()) {
      result.regionArguments.push_back(regionReference(argument.region, span));
      continue;
    }
    if (!argument.binding.empty()) {
      auto item = std::find_if(
          definition.associated.begin(), definition.associated.end(),
          [&](const auto &item) { return item.name == argument.binding; });
      if (item == definition.associated.end()) {
        error("name", argument.span,
              "unknown associated binding '" + argument.binding + "'");
        continue;
      }
      auto value =
          argument.type ? annotation(*argument.type, span, owner)
          : argument.value
              ? constantType(
                    *argument.value,
                    item->constant
                        ? checked.types->parameter(item->parameter).valueType
                        : Type::Unknown)
              : Type::Unknown;
      if (std::any_of(result.associated.begin(), result.associated.end(),
                      [&](const auto &binding) {
                        return binding.parameter == item->parameter;
                      }))
        error("type", argument.span, "duplicate associated binding");
      else
        result.associated.push_back({item->parameter, value});
      continue;
    }
    if (argument.type)
      result.arguments.push_back(annotation(*argument.type, span, owner));
    else if (argument.value)
      result.arguments.push_back(constantType(
          *argument.value,
          supplied < definition.parameters.size() &&
                  checked.types->isConstant(definition.parameters[supplied])
              ? checked.types->parameter(definition.parameters[supplied])
                    .valueType
              : Type::Unknown));
    else
      continue;
    ++supplied;
  }
  std::size_t required = 0;
  auto defaultArgument = [&](const GenericParameter &parameter,
                             std::size_t position) {
    auto &environment = interfaceGenerics.at(&syntax);
    auto identity = definition.parameters[position];
    auto cached = environment.defaults.find(identity);
    Type value;
    if (cached != environment.defaults.end())
      value = cached->second;
    else {
      auto *caller = genericEnvironment;
      genericEnvironment = &environment;
      if (!parameter.defaultType.empty())
        value = annotation(parameter.defaultType, parameter.span);
      else {
        GenericArgument argument;
        argument.value = parameter.defaultValue;
        argument.span = parameter.span;
        value = genericArgument(argument, identity);
      }
      genericEnvironment = caller;
    }
    std::vector<TypeBinding> substitutions;
    if (subject != Type::Unknown)
      substitutions.push_back({definition.self, subject});
    for (std::size_t p = 0;
         p < result.arguments.size() && p < definition.parameters.size(); ++p)
      substitutions.push_back({definition.parameters[p], result.arguments[p]});
    return checked.types->substitute(value, substitutions);
  };
  for (const auto &parameter : syntax.genericParameters) {
    if (parameter.kind == GenericParameterKind::Region)
      continue;
    if (required >= supplied) {
      if (!parameter.defaultType.empty() || parameter.defaultValue)
        result.arguments.push_back(defaultArgument(parameter, required));
      else {
        error("type", span, "interface type argument count does not match");
        result.arguments.push_back(Type::Unknown);
      }
    }
    ++required;
  }
  if (supplied > required)
    error("type", span, "too many interface type arguments");
  for (std::size_t argument = 0; argument < result.arguments.size() &&
                                 argument < definition.parameters.size();
       ++argument) {
    auto parameter = definition.parameters[argument];
    if (!checked.types->isCallable(parameter) ||
        result.arguments[argument] == parameter)
      continue;
    if (requiresRegionProof(parameter, *checked.types))
      error("feature", span,
            "region-bearing callable interface arguments require "
            "declaration-region substitution checking");
  }
  if (bound.arguments.empty())
    for (const auto &name : bound.regions)
      result.regionArguments.push_back(regionReference(name, span));
  auto regionCount = static_cast<std::size_t>(
      std::count_if(syntax.genericParameters.begin(),
                    syntax.genericParameters.end(), [](const auto &parameter) {
                      return parameter.kind == GenericParameterKind::Region;
                    }));
  if (result.regionArguments.size() != regionCount)
    error("type", span, "interface region argument count does not match");
  std::vector<RegionBinding> regionBindings;
  for (std::size_t i = 0;
       i < definition.regions.size() && i < result.regionArguments.size(); ++i)
    regionBindings.push_back(
        {definition.regions[i], result.regionArguments[i]});
  for (const auto &requirement : definition.regionRequirements)
    result.regionRequirements.push_back(
        {checked.types->regions().substitute(requirement.longer,
                                             regionBindings),
         checked.types->regions().substitute(requirement.shorter,
                                             regionBindings)});
  if (result.regionArguments.empty() && result.regionParameters.empty() &&
      result.regionRequirements.empty() &&
      std::none_of(
          result.arguments.begin(), result.arguments.end(),
          [&](auto type) { return checked.types->containsViews(type); }) &&
      std::none_of(result.associated.begin(), result.associated.end(),
                   [&](const auto &binding) {
                     return checked.types->containsViews(binding.argument);
                   }))
    result.regionUniverse = 0;
  auto identity = checked.types->erasedType(std::move(result));
  auto key = std::pair(subject, identity);
  if (!collectingInterfaceAssumptions &&
      checkingInterfaceArguments.insert(key).second) {
    auto assumptions = interfaceAssumptions();
    if (interfacesReady) {
      interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                diagnostics, std::move(assumptions),
                                regionEnvironment());
      solver.wellFormedInterface(subject, identity, span);
    } else
      projectionRequirements.push_back({subject, identity, span,
                                        std::move(assumptions),
                                        regionEnvironment()});
    checkingInterfaceArguments.erase(key);
  }
  if (!bound.binders.empty())
    popRegionParameters();
  return identity;
}

std::vector<interfaces::Obligation> Checker::interfaceAssumptions(
    const GenericEnvironment *inherited,
    const std::function<Type(Type, const TypeSyntax &, Span)> &decorate) {
  std::vector<interfaces::Obligation> result;
  if (!genericEnvironment)
    return result;
  struct Restore {
    bool &flag;
    bool previous;
    ~Restore() { flag = previous; }
  } restore{collectingInterfaceAssumptions, collectingInterfaceAssumptions};
  collectingInterfaceAssumptions = true;
  for (const auto &[subject, bounds] : genericEnvironment->bounds) {
    auto scopedSubject = subject;
    if (!annotationRegionScopes.empty() && checked.types->isView(subject))
      for (const auto *constraint : genericEnvironment->boundConstraints) {
        if (constraint->region || constraint->bounds.empty())
          continue;
        auto candidate = annotation(constraint->subject, constraint->span);
        if (checked.types->eraseRegions(candidate) ==
            checked.types->eraseRegions(subject)) {
          scopedSubject = candidate;
          break;
        }
      }
    std::size_t first = 0;
    if (inherited)
      if (auto outer = inherited->bounds.find(subject);
          outer != inherited->bounds.end())
        first = outer->second.size();
    for (std::size_t i = first; i < bounds.size(); ++i) {
      const auto &bound = bounds[i];
      if (bound.form == TypeForm::Callable)
        continue;
      if (bound.name == "unsized")
        continue;
      auto context = genericEnvironment->declarationSpan;
      auto property = propertyBound(bound, context)
                          .value_or(interfaces::Property::Interface);
      if (property == interfaces::Property::Interface &&
          !elaboratingBounds.insert(&bound).second)
        continue;
      auto type = property == interfaces::Property::Interface
                      ? interfaceBound(bound, context, {}, scopedSubject)
                      : Type::Unknown;
      if (decorate && property == interfaces::Property::Interface)
        type = decorate(type, bound, context);
      if (property == interfaces::Property::Interface)
        elaboratingBounds.erase(&bound);
      result.push_back({scopedSubject, type, property});
    }
  }
  expandSuperinterfaces(result);
  return result;
}

std::vector<interfaces::Obligation>
Checker::resolveSuperinterfaces(std::size_t index) {
  const auto &syntax = module.interfaces[index];
  const auto self = checked.interfaceData->definitions[index].self;
  std::vector<interfaces::Obligation> result;
  for (const auto &parentBound : syntax.superinterfaces) {
    if (auto property = propertyBound(parentBound, syntax.span))
      result.push_back({self, Type::Unknown, *property});
    else
      result.push_back(
          {self, interfaceBound(parentBound, syntax.span, {}, self)});
  }
  return result;
}

// Extension bounds are resolved before interface signatures, so a projection
// such as `I.Item` through `I: ExactSizeIterator` needs the parents early.
// Region-parameterized interfaces bind their regions only during signatures.
const std::vector<interfaces::Obligation> &
Checker::superinterfacesOf(std::size_t index) {
  const auto &definition = checked.interfaceData->definitions[index];
  if (signedSuperinterfaces.contains(index))
    return definition.superinterfaces;
  if (auto early = earlySuperinterfaces.find(index);
      early != earlySuperinterfaces.end())
    return early->second;
  static const std::vector<interfaces::Obligation> none;
  const auto &syntax = module.interfaces[index];
  if (std::any_of(syntax.genericParameters.begin(),
                  syntax.genericParameters.end(), [](const auto &parameter) {
                    return parameter.kind == GenericParameterKind::Region;
                  }))
    return none;
  if (!resolvingSuperinterfaces.insert(index).second)
    return none;
  auto *saved = genericEnvironment;
  genericEnvironment = &interfaceGenerics.at(&syntax);
  auto parents = resolveSuperinterfaces(index);
  genericEnvironment = saved;
  resolvingSuperinterfaces.erase(index);
  return earlySuperinterfaces.emplace(index, std::move(parents)).first->second;
}

void Checker::expandSuperinterfaces(
    std::vector<interfaces::Obligation> &result) {
  std::set<std::pair<Type, Type>> expanded;
  for (std::size_t index = 0; index < result.size(); ++index) {
    auto obligation = result[index];
    if (obligation.property != interfaces::Property::Interface ||
        !checked.types->isErased(obligation.interfaceType) ||
        !expanded.emplace(obligation.subject, obligation.interfaceType).second)
      continue;
    const auto descriptor = checked.types->erased(obligation.interfaceType);
    const auto &definition =
        checked.interfaceData->definitions[descriptor.declaration];
    std::vector<TypeBinding> substitutions{
        {definition.self, obligation.subject}};
    for (std::size_t i = 0;
         i < definition.parameters.size() && i < descriptor.arguments.size();
         ++i)
      substitutions.push_back(
          {definition.parameters[i], descriptor.arguments[i]});
    for (auto parent : superinterfacesOf(descriptor.declaration)) {
      parent.subject = checked.types->substitute(parent.subject, substitutions);
      parent.interfaceType =
          checked.types->substitute(parent.interfaceType, substitutions);
      result.push_back(parent);
    }
    if (result.size() > limits::activeLoans) {
      error("limit", {}, "interface bound elaboration limit exceeded");
      break;
    }
  }
}

bool Checker::unpinObligation(Type type, Span span) {
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (genericEnvironment)
    solver.setEqualities(genericEnvironment->equalities);
  return solver.prove({type, Type::Unknown, interfaces::Property::Unpin}, span,
                      false);
}
bool Checker::interfaceObligation(Type actual, const TypeSyntax &bound,
                                  Span span) {
  if (bound.name == "unsized")
    return true;
  const auto property =
      propertyBound(bound, span).value_or(interfaces::Property::Interface);
  auto interfaceType = property == interfaces::Property::Interface
                           ? interfaceBound(bound, span, {}, actual)
                           : Type::Unknown;
  interfaces::Obligation obligation{actual, interfaceType, property};
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (solver.prove(obligation, span, false))
    return true;
  if (property != interfaces::Property::Interface) {
    error("type", span,
          "unsatisfied interface bound '" + displayPath(bound.name) + "'");
    return false;
  }
  const std::array<Type, 2> namesInMessage{actual, interfaceType};
  const auto subject = displayType(*checked.types, actual, namesInMessage);
  const auto interface =
      displayType(*checked.types, interfaceType, namesInMessage);
  error(
      "type", span,
      "unsatisfied interface bound '" + displayPath(bound.name) + "'",
      {{"note",
        {},
        "no implementation of '" + interface + "' is available for '" +
            subject + "'"},
       {"help",
        {},
        "add `extend " + subject + " implements " + interface + " { ... }`"}});
  return false;
}
bool Checker::interfaceObligation(Type actual, Type interfaceType, Span span,
                                  std::vector<RegionId> *staticRegions) {
  auto assumptions = interfaceAssumptions();
  if (checked.types->isErased(actual))
    assumptions.push_back({actual, actual});
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            std::move(assumptions), regionEnvironment());
  if (staticRegions)
    solver.collectStaticRegions(staticRegions);
  if (solver.prove({actual, interfaceType}, span, false))
    return true;
  // An f-string hole is filled through core::fmt::Hole; say what is missing in
  // the user's terms rather than naming that internal interface.
  if (checked.types->isErased(interfaceType) &&
      checked.interfaceData
              ->definitions[checked.types->erased(interfaceType).declaration]
              .name == "core::fmt::Hole") {
    error("type", span,
          "a value of this type cannot fill an f-string hole; it must be "
          "Text or implement core.fmt.Display");
    return false;
  }
  const std::array<Type, 2> namesInMessage{actual, interfaceType};
  const auto subject = displayType(*checked.types, actual, namesInMessage);
  const auto interface =
      displayType(*checked.types, interfaceType, namesInMessage);
  error(
      "type", span,
      "unsatisfied interface obligation: no implementation of '" + interface +
          "' is available for '" + subject + "'",
      {{"help",
        {},
        "add `extend " + subject + " implements " + interface + " { ... }`"}});
  return false;
}
Type Checker::normalizeGenericType(Type type,
                                   std::span<const TypeBinding> bindings,
                                   Span span) {
  std::vector<TypeBinding> substitutions(bindings.begin(), bindings.end());
  if (genericEnvironment)
    substitutions.insert(substitutions.end(),
                         genericEnvironment->equalities.begin(),
                         genericEnvironment->equalities.end());
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  auto normalized = solver.normalize(type, substitutions, span);
  return annotationRegionScopes.empty()
             ? checked.types->eraseRegions(normalized)
             : normalized;
}
Type Checker::normalizeCallType(Type type,
                                std::span<const TypeBinding> bindings,
                                const Function &callee, Span span) {
  std::vector<TypeBinding> substitutions(bindings.begin(), bindings.end());
  if (genericEnvironment)
    substitutions.insert(substitutions.end(),
                         genericEnvironment->equalities.begin(),
                         genericEnvironment->equalities.end());
  auto regions = regionEnvironment();
  const auto &declaration = functionRegions(callee).environment;
  regions.assumptions.insert(regions.assumptions.end(),
                             declaration.assumptions.begin(),
                             declaration.assumptions.end());
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), std::move(regions));
  return checked.types->eraseRegions(
      solver.normalize(type, substitutions, span));
}

void Checker::interfaceSignatures() {
  auto *saved = genericEnvironment;
  for (std::size_t i = 0; i < module.interfaces.size(); ++i) {
    const auto &syntax = module.interfaces[i];
    if (imported(syntax.span))
      continue;
    auto &definition = checked.interfaceData->definitions[i];
    auto &environment = interfaceGenerics.at(&syntax);
    definition.parameters = environment.parameters;
    TypeSyntax selfBound;
    selfBound.name = syntax.name;
    for (const auto &parameter : syntax.genericParameters) {
      GenericArgument argument;
      if (parameter.kind == GenericParameterKind::Type) {
        auto type = std::make_shared<TypeSyntax>();
        type->name = parameter.name;
        argument.type = std::move(type);
      } else if (parameter.kind == GenericParameterKind::Const) {
        auto value = std::make_shared<Node>();
        value->kind = Kind::Name;
        value->text = parameter.name;
        value->span = parameter.span;
        argument.value = std::move(value);
      } else
        argument.region = {parameter.name, parameter.nameSpan,
                           parameter.context};
      selfBound.arguments.push_back(std::move(argument));
    }
    environment.bounds[definition.self].push_back(std::move(selfBound));
    genericEnvironment = &environment;
    definition.regions =
        pushRegionParameters(syntax.genericParameters, syntax.span);
    assumeRegionConstraints(syntax.constraints, syntax.span);
    if (std::any_of(syntax.genericParameters.begin(),
                    syntax.genericParameters.end(), [](const auto &parameter) {
                      return parameter.kind == GenericParameterKind::Region;
                    }))
      validateGenericEnvironment(syntax.genericParameters, syntax.constraints,
                                 environment);
    definition.regionRequirements = regionEnvironment().assumptions;
    definition.requirements = interfaceAssumptions();
    std::erase_if(definition.requirements, [&](const auto &requirement) {
      return requirement.subject == definition.self &&
             checked.types->isErased(requirement.interfaceType) &&
             checked.types->erased(requirement.interfaceType).declaration == i;
    });
    definition.equalities = environment.equalities;
    for (std::size_t associated = 0; associated < syntax.associated.size();
         ++associated) {
      const auto &item = syntax.associated[associated];
      auto &family =
          associatedGenerics
              .emplace(&item, makeGenericEnvironment(item.genericParameters,
                                                     item.constraints,
                                                     genericEnvironment))
              .first->second;
      family.declarationSpan = item.span;
      auto *outer = genericEnvironment;
      genericEnvironment = &family;
      auto &compiled = definition.associated[associated];
      if (item.constant)
        checked.types->setConstantParameterType(
            compiled.parameter, annotation(item.annotation, item.span));
      auto prefix = definition.parameters.size();
      compiled.parameters.assign(family.parameters.begin() + prefix,
                                 family.parameters.end());
      auto outerRequirements = regionEnvironment().assumptions.size();
      compiled.regions =
          pushRegionParameters(item.genericParameters, item.span);
      assumeRegionConstraints(item.constraints, item.span);
      validateGenericEnvironment(item.genericParameters, item.constraints,
                                 family);
      compiled.requirements = interfaceAssumptions(outer);
      compiled.equalities.assign(family.equalities.begin() +
                                     outer->equalities.size(),
                                 family.equalities.end());
      for (auto parameter : compiled.parameters)
        if (auto value = family.defaults.find(parameter);
            value != family.defaults.end())
          compiled.defaults.push_back({parameter, value->second});
      for (const auto &bound : item.bounds) {
        if (bound.name == "unsized")
          continue;
        auto property = propertyBound(bound, item.span)
                            .value_or(interfaces::Property::Interface);
        compiled.bounds.push_back(
            {compiled.parameter,
             property == interfaces::Property::Interface
                 ? interfaceBound(bound, item.span, {}, compiled.parameter)
                 : Type::Unknown,
             property});
      }
      const auto &requirements = regionEnvironment().assumptions;
      compiled.regionRequirements.assign(
          requirements.begin() + outerRequirements, requirements.end());
      compiled.defaultValue =
          item.constant
              ? item.constantValue
                    ? constantType(*item.constantValue,
                                   checked.types->parameter(compiled.parameter)
                                       .valueType)
                    : Type::Unknown
          : !item.value.empty() ? annotation(item.value, item.span)
                                : Type::Unknown;
      if (!item.constant && compiled.defaultValue != Type::Unknown &&
          !item.asyncFutureDefaultInferred) {
        if (checked.types->isSized(compiled.parameter) &&
            !checked.types->isSized(compiled.defaultValue))
          error("type", item.span,
                "associated default type does not satisfy Sized");
        if (checked.types->isCopy(compiled.parameter) &&
            !checked.types->isCopy(compiled.defaultValue))
          error("type", item.span,
                "associated default type does not satisfy Copy");
        if (checked.types->isUnpin(compiled.parameter) &&
            !unpinObligation(compiled.defaultValue, item.span))
          error("type", item.span,
                "associated default type does not satisfy Unpin");
      }
      popRegionParameters();
      genericEnvironment = outer;
    }
    if (auto early = earlySuperinterfaces.find(i);
        early != earlySuperinterfaces.end())
      definition.superinterfaces = std::move(early->second);
    else
      definition.superinterfaces = resolveSuperinterfaces(i);
    signedSuperinterfaces.insert(i);
    popRegionParameters();
  }
  std::vector<unsigned char> states(module.interfaces.size());
  std::function<void(std::size_t, unsigned)> visit = [&](std::size_t index,
                                                         unsigned depth) {
    if (states[index] == 2)
      return;
    if (states[index] == 1) {
      error("type", module.interfaces[index].span,
            "cyclic superinterface requirements");
      return;
    }
    if (depth > limits::typeDepth) {
      error("limit", module.interfaces[index].span,
            "superinterface nesting limit exceeded");
      return;
    }
    states[index] = 1;
    for (const auto &parent :
         checked.interfaceData->definitions[index].superinterfaces)
      if (parent.property == interfaces::Property::Interface &&
          checked.types->isErased(parent.interfaceType))
        visit(checked.types->erased(parent.interfaceType).declaration,
              depth + 1);
    states[index] = 2;
  };
  for (std::size_t index = 0; index < states.size(); ++index)
    visit(index, 0);
  for (auto &function : module.functions) {
    if (imported(function.span))
      continue;
    auto &environment = functionGenerics.at(&function);
    genericEnvironment = &environment;
    if (function.implementation >= 0)
      environment.names[nameKey("Self", function.lexicalContext)] =
          annotation(module.implementations[function.implementation].target,
                     function.span);
    // A bare interface parameter accessed through `read` or `mut` is only
    // borrowed, so its implicit parameter may be unsized; by-value use keeps
    // the default Sized requirement.
    std::function<void(const TypeSyntax &, Span, bool)> implicit =
        [&](const TypeSyntax &type, Span span, bool borrowed) {
          if (type.form == TypeForm::Erased || type.form == TypeForm::Opaque ||
              type.form == TypeForm::Projection)
            return;
          if (type.form == TypeForm::Named && !type.name.empty() &&
              !environment.names.contains(nameKey(type.name, type.context))) {
            auto canonical =
                typeName(type.name, span, function.owner, type.context);
            auto found = interfaceNames.find(canonical);
            if (found != interfaceNames.end()) {
              auto subject = checked.types->declareParameter(
                  definitionName(function.span, function.name) + ".<input." +
                      std::to_string(environment.parameters.size()) + ">",
                  interfaceProperty(type, "Copy", span), !borrowed);
              implicitInterfaceParameters[&type] = subject;
              environment.parameters.push_back(subject);
              environment.bounds[subject].push_back(type);
            }
          }
          if (type.nested)
            implicit(*type.nested, span, false);
          for (const auto &element : type.elements)
            implicit(element, span, false);
        };
    for (const auto &parameter : function.parameters)
      implicit(parameter.annotation, parameter.span,
               parameter.mode == "read" || parameter.mode == "mut" ||
                   parameter.mode.empty());
  }
  genericEnvironment = saved;
}

Type Checker::interfaceProjection(Type subject, Type interfaceType,
                                  std::string_view member,
                                  std::span<const GenericArgument> arguments,
                                  Span span) {
  if (!checked.types->isErased(interfaceType))
    return Type::Unknown;
  const auto bound = checked.types->erased(interfaceType);
  const auto &definition =
      checked.interfaceData->definitions[bound.declaration];
  auto associated =
      std::find_if(definition.associated.begin(), definition.associated.end(),
                   [&](const auto &item) { return item.name == member; });
  if (associated == definition.associated.end()) {
    error("name", span,
          "unknown associated item '" + std::string(member) + "'");
    return Type::Unknown;
  }
  for (const auto &binding : bound.associated)
    if (binding.parameter == associated->parameter)
      return binding.argument;
  std::vector<Type> actuals;
  std::vector<RegionId> regions;
  for (const auto &argument : arguments)
    if (!argument.region.empty())
      regions.push_back(regionReference(argument.region, span));
    else if (argument.type)
      actuals.push_back(annotation(*argument.type, span));
    else if (argument.value) {
      auto position = actuals.size();
      actuals.push_back(constantType(
          *argument.value,
          position < associated->parameters.size() &&
                  checked.types->isConstant(associated->parameters[position])
              ? checked.types->parameter(associated->parameters[position])
                    .valueType
              : Type::Unknown));
    }
  if (regions.size() != associated->regions.size())
    error("type", span,
          "associated family region argument count does not match");
  auto ordinal =
      static_cast<std::size_t>(associated - definition.associated.begin());
  auto projection = checked.types->projection(
      subject, interfaceType, static_cast<std::uint32_t>(ordinal), actuals,
      associated->constant
          ? checked.types->parameter(associated->parameter).valueType
          : Type::Unknown,
      checked.types->isCopy(associated->parameter),
      checked.types->isSized(associated->parameter), regions);
  auto &projections = checked.interfaceData->projections;
  if (std::none_of(
          projections.begin(), projections.end(),
          [&](const auto &prior) { return prior.parameter == projection; }))
    projections.push_back({projection, subject, interfaceType, ordinal,
                           std::move(actuals), std::move(regions)});
  auto assumptions = interfaceAssumptions();
  if (!interfacesReady)
    projectionRequirements.push_back({subject, interfaceType, span, assumptions,
                                      regionEnvironment(), projection});
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            std::move(assumptions), regionEnvironment());
  if (interfacesReady && !solver.prove({subject, interfaceType}, span, false)) {
    error("type", span, "associated projection requires its interface bound");
    return Type::Unknown;
  }
  return solver.normalize(projection, {}, span);
}

std::optional<Type> Checker::interfaceAnnotation(const TypeSyntax &syntax,
                                                 Span span,
                                                 std::string_view owner) {
  if (auto implicit = implicitInterfaceParameters.find(&syntax);
      implicit != implicitInterfaceParameters.end())
    return implicit->second;
  if (syntax.form == TypeForm::Erased) {
    if (syntax.elements.size() != 1) {
      error("type", span, "erasure requires exactly one interface");
      return Type::Unknown;
    }
    auto result = interfaceBound(syntax.elements[0], span, owner);
    if (result != Type::Unknown)
      erasedUses.emplace(result, span);
    return result;
  }
  if (syntax.form == TypeForm::Opaque) {
    if (auto found = opaqueDeclarations.find(&syntax);
        found != opaqueDeclarations.end())
      return found->second;
    bool copy = false;
    for (const auto &bound : syntax.elements)
      copy |= interfaceProperty(bound, "Copy", span);
    auto name = current ? definitionName(current->span, current->name)
                        : definitionName(span, "<opaque>");
    auto type = checked.types->opaqueType(
        name + ".<opaque." + std::to_string(opaqueDeclarations.size()) + ">",
        Type::Unknown, {}, copy);
    checked.types->setProductPackage(
        type, checked.namespaces().packageOf(span).value_or(unknownPackage));
    opaqueDeclarations.emplace(&syntax, type);
    if (std::any_of(syntax.elements.begin(), syntax.elements.end(),
                    [&](const auto &bound) {
                      return interfaceProperty(bound, "Unpin", span);
                    })) {
      auto layout = checked.types->product(type).layout;
      layout.unpin = 1;
      checked.types->setProductLayout(type, std::move(layout));
    }
    std::vector<Type> bounds;
    for (const auto &bound : syntax.elements)
      if (!propertyBound(bound, span))
        bounds.push_back(interfaceBound(bound, span, owner, type));
    checked.types->setOpaqueBounds(type, std::move(bounds));
    if (current) {
      facts(*current).opaqueResult = type;
      checked.types->setGenericParameters(type, genericBindings(*current));
    }
    return type;
  }
  if (syntax.form == TypeForm::Projection && syntax.elements.size() == 2) {
    auto subject = annotation(syntax.elements[0], span, owner);
    auto bound = interfaceBound(syntax.elements[1], span, owner, subject);
    return interfaceProjection(subject, bound, syntax.name, syntax.arguments,
                               span);
  }
  if (syntax.form == TypeForm::Named) {
    auto delimiter = syntax.name.rfind("::");
    if (delimiter != std::string::npos && genericEnvironment) {
      auto subject = genericEnvironment->names.find(
          nameKey(syntax.name.substr(0, delimiter), syntax.context));
      if (subject != genericEnvironment->names.end()) {
        auto bounds = genericEnvironment->bounds.find(subject->second);
        if (bounds != genericEnvironment->bounds.end()) {
          // Associated names declared by superinterfaces are reachable
          // through the elaborated bound set.
          std::vector<interfaces::Obligation> elaborated;
          for (const auto &bound : bounds->second) {
            if (propertyBound(bound, span) || bound.name == "unsized")
              continue;
            auto interface =
                interfaceBound(bound, span, owner, subject->second);
            if (checked.types->isErased(interface))
              elaborated.push_back({subject->second, interface});
          }
          expandSuperinterfaces(elaborated);
          auto name = syntax.name.substr(delimiter + 2);
          Type declaring = Type::Unknown;
          for (const auto &obligation : elaborated) {
            if (obligation.property != interfaces::Property::Interface ||
                obligation.subject != subject->second ||
                !checked.types->isErased(obligation.interfaceType) ||
                obligation.interfaceType == declaring)
              continue;
            const auto &definition =
                checked.interfaceData
                    ->definitions[checked.types
                                      ->erased(obligation.interfaceType)
                                      .declaration];
            if (std::none_of(
                    definition.associated.begin(), definition.associated.end(),
                    [&](const auto &item) { return item.name == name; }))
              continue;
            if (declaring != Type::Unknown) {
              error("type", span, "ambiguous associated projection");
              return Type::Unknown;
            }
            declaring = obligation.interfaceType;
          }
          Type projection = Type::Unknown;
          if (declaring != Type::Unknown)
            projection = interfaceProjection(subject->second, declaring, name,
                                             syntax.arguments, span);
          if (projection != Type::Unknown)
            return projection;
        }
      }
    }
  }
  return std::nullopt;
}
} // namespace mettle
