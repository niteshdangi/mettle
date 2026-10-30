#include "semantics/checker.h"
#include "support/limits.h"
#include <algorithm>
#include <functional>

namespace mettle {
void Checker::interfaceHeaders() {
  if (module.interfaces.size() > limits::interfaces) {
    error("limit", {}, "interface declaration limit exceeded");
    return;
  }
  auto &database = *checked.interfaceData;
  for (const auto &syntax : module.interfaces) {
    auto name = definitionName(syntax.span, syntax.name);
    if (!interfaceNames.emplace(name, database.definitions.size()).second) {
      error("name", syntax.span, "duplicate interface '" + syntax.name + "'");
      continue;
    }
    interfaces::Definition definition;
    definition.name = name;
    definition.span = syntax.span;
    definition.self =
        checked.types->declareParameter(name + ".Self", false, false);
    database.definitions.push_back(std::move(definition));
  }
  if (!diagnostics.empty())
    return;
  for (std::size_t index = 0; index < module.interfaces.size(); ++index) {
    const auto &syntax = module.interfaces[index];
    auto &definition = database.definitions[index];
    const auto &name = definition.name;
    for (const auto &associated : syntax.associated) {
      interfaces::Associated item;
      item.name = associated.name;
      item.constant = associated.constant;
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
         !checked.namespaces().lookup(checked.namespaces().moduleOf(span),
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
        auto canonical = typeName(current.name, context);
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
  auto canonical = typeName(bound.name, span, owner);
  auto found = interfaceNames.find(canonical);
  if (found == interfaceNames.end()) {
    error("type", span, "unknown interface bound '" + bound.name + "'");
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
      parameter.name = name;
      parameter.span = span;
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
  if (!bound.binders.empty())
    popRegionParameters();
  return identity;
}

std::vector<interfaces::Obligation> Checker::interfaceAssumptions() {
  std::vector<interfaces::Obligation> result;
  if (!genericEnvironment)
    return result;
  for (const auto &[subject, bounds] : genericEnvironment->bounds)
    for (const auto &bound : bounds) {
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
                      ? interfaceBound(bound, context, {}, subject)
                      : Type::Unknown;
      if (property == interfaces::Property::Interface)
        elaboratingBounds.erase(&bound);
      result.push_back({subject, type, property});
    }
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
    for (auto parent : definition.superinterfaces) {
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
  return result;
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
  interfaces::Obligation obligation{
      actual, Type::Unknown,
      propertyBound(bound, span).value_or(interfaces::Property::Interface)};
  if (obligation.property == interfaces::Property::Interface)
    obligation.interfaceType = interfaceBound(bound, span, {}, actual);
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (solver.prove(obligation, span, false))
    return true;
  error("type", span, "unsatisfied interface bound '" + bound.name + "'");
  return false;
}
bool Checker::interfaceObligation(Type actual, Type interfaceType, Span span) {
  auto assumptions = interfaceAssumptions();
  if (checked.types->isErased(actual))
    assumptions.push_back({actual, actual});
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            std::move(assumptions), regionEnvironment());
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
          "Text or implement core::fmt::Display");
    return false;
  }
  error("type", span, "unsatisfied interface obligation");
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
        argument.region = parameter.name;
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
    for (std::size_t associated = 0; associated < syntax.associated.size();
         ++associated) {
      const auto &item = syntax.associated[associated];
      auto family = makeGenericEnvironment(
          item.genericParameters, item.constraints, genericEnvironment);
      auto *outer = genericEnvironment;
      genericEnvironment = &family;
      auto &compiled = definition.associated[associated];
      if (item.constant)
        checked.types->setConstantParameterType(
            compiled.parameter, annotation(item.annotation, item.span));
      auto prefix = definition.parameters.size();
      compiled.parameters.assign(family.parameters.begin() + prefix,
                                 family.parameters.end());
      compiled.requirements = interfaceAssumptions();
      auto outerRequirements = regionEnvironment().assumptions.size();
      compiled.regions =
          pushRegionParameters(item.genericParameters, item.span);
      assumeRegionConstraints(item.constraints, item.span);
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
      if (!item.constant && compiled.defaultValue != Type::Unknown) {
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
    for (const auto &parentBound : syntax.superinterfaces) {
      if (auto property = propertyBound(parentBound, syntax.span))
        definition.superinterfaces.push_back(
            {definition.self, Type::Unknown, *property});
      else
        definition.superinterfaces.push_back(
            {definition.self,
             interfaceBound(parentBound, syntax.span, {}, definition.self)});
    }
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
    auto &environment = functionGenerics.at(&function);
    genericEnvironment = &environment;
    if (function.implementation >= 0)
      environment.names["Self"] =
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
              !environment.names.contains(type.name)) {
            auto canonical = typeName(type.name, span, function.owner);
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
    projectionRequirements.push_back(
        {subject, interfaceType, span, assumptions, regionEnvironment()});
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
      auto subject =
          genericEnvironment->names.find(syntax.name.substr(0, delimiter));
      if (subject != genericEnvironment->names.end()) {
        auto bounds = genericEnvironment->bounds.find(subject->second);
        if (bounds != genericEnvironment->bounds.end()) {
          Type projection = Type::Unknown;
          for (const auto &bound : bounds->second) {
            if (propertyBound(bound, span) || bound.name == "unsized")
              continue;
            auto interface =
                interfaceBound(bound, span, owner, subject->second);
            if (!checked.types->isErased(interface))
              continue;
            const auto &definition =
                checked.interfaceData
                    ->definitions[checked.types->erased(interface).declaration];
            if (std::none_of(
                    definition.associated.begin(), definition.associated.end(),
                    [&](const auto &item) {
                      return item.name == syntax.name.substr(delimiter + 2);
                    }))
              continue;
            if (projection != Type::Unknown) {
              error("type", span, "ambiguous associated projection");
              return Type::Unknown;
            }
            projection = interfaceProjection(subject->second, interface,
                                             syntax.name.substr(delimiter + 2),
                                             syntax.arguments, span);
          }
          if (projection != Type::Unknown)
            return projection;
        }
      }
    }
  }
  return std::nullopt;
}
} // namespace mettle
