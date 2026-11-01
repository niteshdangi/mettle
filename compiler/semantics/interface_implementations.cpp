#include "semantics/checker.h"
#include "support/path.h"
#include <algorithm>
#include <utility>

namespace mettle {
// Manual declarations of the structural cross-thread properties: a negative
// `extend T not Transferable;` or an `unsafe extend ... implements
// Transferable {}` whose bounds state the conditions the implementer has
// verified.
void Checker::concurrencyDeclaration(
    const Module::Implementation &syntax, interfaces::Property property,
    interfaces::Implementation &implementation) {
  auto &database = *checked.interfaceData;
  const std::string name =
      property == interfaces::Property::Transferable ? "Transferable"
      : property == interfaces::Property::Shareable  ? "Shareable"
                                                     : "Static";
  if (property == interfaces::Property::Static) {
    error("type", syntax.span, "Static is derived and cannot be declared");
    return;
  }
  auto target = implementation.target;
  if (!checked.types->isProduct(target) || checked.types->isOpaque(target) ||
      (checked.types->product(target).kind != AggregateKind::Product &&
       checked.types->product(target).kind != AggregateKind::Enumeration) ||
      checked.types->product(target).callable >= 0) {
    error("type", syntax.span,
          name + " declarations require a local nominal type");
    return;
  }
  auto origin = checked.types->product(target).genericOrigin;
  if (origin == Type::Unknown)
    origin = target;
  if (checked.types->product(origin).package != 0)
    error("type", syntax.span,
          name + " declaration must belong to the type's package");
  if (!syntax.negative && !syntax.unsafeImplementation)
    error("unsafe", syntax.span,
          "manual " + name + " implementation requires an unsafe extend");
  if (syntax.negative && syntax.unsafeImplementation)
    error("type", syntax.span, "negative " + name + " declarations are safe");
  if (!syntax.associated.empty() || !syntax.methodFunctions.empty())
    error("type", syntax.span,
          name + " declarations cannot contain associated items");
  const auto &arguments = checked.types->product(target).genericArguments;
  const auto &parameters = checked.types->product(origin).genericParameters;
  if (arguments.size() != parameters.size())
    error("type", syntax.span,
          name + " declaration must cover every type parameter");
  std::set<Type> used;
  for (auto argument : arguments) {
    bool constant =
        checked.types->isConstant(argument) &&
        checked.types->parameter(argument).kind == TypeParameterKind::Constant;
    if ((!checked.types->isParameter(argument) && !constant) ||
        !used.insert(argument).second)
      error("type", syntax.span,
            "specialized " + name + " declarations are not coherent");
  }
  if (syntax.negative &&
      (!syntax.constraints.empty() ||
       std::any_of(syntax.genericParameters.begin(),
                   syntax.genericParameters.end(),
                   [](const auto &p) { return !p.bounds.empty(); })))
    error("type", syntax.span,
          "negative " + name + " declarations cannot specialize bounds");
  implementation.requirements = interfaceAssumptions();
  auto [position, inserted] = database.concurrencyDeclarations.emplace(
      std::make_pair(property, origin),
      interfaces::ConcurrencyDeclaration{syntax.negative, implementation});
  if (!inserted)
    error("type", syntax.span, "overlapping " + name + " declarations");
}

void Checker::interfaceImplementations() {
  auto &database = *checked.interfaceData;
  auto *saved = genericEnvironment;
  for (std::size_t function = 0; function < module.functions.size();
       ++function) {
    const auto &syntax = module.functions[function];
    if (syntax.interfaceOwner.empty() || syntax.implementation >= 0)
      continue;
    auto name = typeName(syntax.interfaceOwner, syntax.span);
    auto interface = interfaceNames.find(name);
    if (interface == interfaceNames.end())
      continue;
    auto delimiter = syntax.name.rfind('.');
    auto methodName = syntax.name.substr(delimiter + 1);
    auto &methods = database.definitions[interface->second].methods;
    if (std::any_of(methods.begin(), methods.end(), [&](const auto &method) {
          return method.name == methodName;
        }))
      error("name", syntax.span, "duplicate interface method");
    interfaces::Method method;
    method.name = methodName;
    method.function = static_cast<int>(function);
    method.implicitParameters =
        1 + database.definitions[interface->second].parameters.size();
    methods.push_back(std::move(method));
  }
  for (std::size_t i = 0; i < module.implementations.size(); ++i) {
    const auto &syntax = module.implementations[i];
    auto foundEnvironment = implementationGenerics.find(&syntax);
    if (foundEnvironment == implementationGenerics.end()) {
      auto environment =
          makeGenericEnvironment(syntax.genericParameters, syntax.constraints);
      environment.declarationSpan = syntax.span;
      foundEnvironment =
          implementationGenerics.emplace(&syntax, std::move(environment)).first;
    }
    genericEnvironment = &foundEnvironment->second;
    auto implementationRegions =
        pushRegionParameters(syntax.genericParameters, syntax.span);
    assumeRegionConstraints(syntax.constraints, syntax.span);
    interfaces::Implementation implementation;
    implementation.declaration = i;
    implementation.span = syntax.span;
    implementation.parameters = genericEnvironment->parameters;
    implementation.regions = std::move(implementationRegions);
    implementation.regionRequirements = regionEnvironment().assumptions;
    implementation.target = annotation(syntax.target, syntax.span);
    genericEnvironment->names["Self"] = implementation.target;
    validateGenericEnvironment(syntax.genericParameters, syntax.constraints,
                               *genericEnvironment);
    implementation.equalities = genericEnvironment->equalities;
    implementation.target = checked.types->substitute(
        implementation.target, implementation.equalities);
    genericEnvironment->names["Self"] = implementation.target;
    if (intrinsicProperty(syntax.interface, "Unpin", syntax.span)) {
      auto target = implementation.target;
      if (!checked.types->isProduct(target) ||
          checked.types->isOpaque(target) ||
          checked.types->product(target).kind != AggregateKind::Product) {
        error("type", syntax.span,
              "Unpin implementations require a local nominal type");
      } else {
        auto origin = checked.types->product(target).genericOrigin;
        if (origin == Type::Unknown)
          origin = target;
        auto layout = checked.types->product(origin).layout;
        if (layout.unpin >= 0)
          error("type", syntax.span, "overlapping Unpin declarations");
        if (!syntax.negative && !syntax.unsafeImplementation)
          error("unsafe", syntax.span,
                "manual Unpin implementation requires an unsafe extend");
        if (checked.types->product(origin).package != 0)
          error("type", syntax.span,
                "Unpin implementation must belong to the type's package");
        if (!syntax.associated.empty() || !syntax.methodFunctions.empty())
          error("type", syntax.span,
                "Unpin declarations cannot contain associated items");
        const auto &arguments = checked.types->product(target).genericArguments;
        const auto &parameters =
            checked.types->product(origin).genericParameters;
        if (arguments.size() != parameters.size())
          error("type", syntax.span,
                "Unpin declaration must cover every type parameter");
        std::set<Type> used;
        for (std::size_t p = 0; p < arguments.size(); ++p) {
          auto argument = arguments[p];
          bool constant = checked.types->isConstant(argument) &&
                          checked.types->parameter(argument).kind ==
                              TypeParameterKind::Constant;
          if ((!checked.types->isParameter(argument) && !constant) ||
              !used.insert(argument).second) {
            error("type", syntax.span,
                  "specialized Unpin declarations are not coherent");
            continue;
          }
          auto flags = constant
                           ? 0u
                           : (checked.types->isCopy(argument) ? 1u : 0u) |
                                 (checked.types->isSized(argument) ? 2u : 0u) |
                                 (checked.types->isUnpin(argument) ? 4u : 0u);
          if (flags)
            layout.unpinConditions.emplace_back(p, flags);
        }
        implementation.requirements = interfaceAssumptions();
        layout.unpin = syntax.negative ? 0 : 1;
        layout.conditionalUnpin = !implementation.requirements.empty() ||
                                  !implementation.regionRequirements.empty() ||
                                  !implementation.equalities.empty();
        if (syntax.negative &&
            (!syntax.constraints.empty() ||
             std::any_of(syntax.genericParameters.begin(),
                         syntax.genericParameters.end(),
                         [](const auto &p) { return !p.bounds.empty(); })))
          error("type", syntax.span,
                "negative Unpin declarations cannot specialize bounds");
        if (!syntax.negative)
          database.unpinImplementations.emplace(origin, implementation);
        checked.types->setProductLayout(origin, std::move(layout));
        checked.types->refreshProductInstances();
      }
      popRegionParameters();
      continue;
    }
    if (auto property = propertyBound(syntax.interface, syntax.span);
        property && (*property == interfaces::Property::Transferable ||
                     *property == interfaces::Property::Shareable ||
                     *property == interfaces::Property::Static)) {
      concurrencyDeclaration(syntax, *property, implementation);
      popRegionParameters();
      continue;
    }
    if (syntax.negative)
      error("feature", syntax.span,
            "this negative property is not implemented");
    if (syntax.unsafeImplementation)
      error("type", syntax.span,
            "unsafe extend requires an unsafe native property");
    if (!syntax.interface.empty())
      implementation.interfaceType = interfaceBound(
          syntax.interface, syntax.span, {}, implementation.target);
    implementation.requirements = interfaceAssumptions();
    if (!syntax.interface.empty() &&
        checked.types->isErased(implementation.interfaceType)) {
      auto interfaceDeclaration =
          checked.types->erased(implementation.interfaceType).declaration;
      const auto &definition = database.definitions[interfaceDeclaration];
      for (std::size_t item = 0; item < definition.associated.size(); ++item) {
        const auto &required = definition.associated[item];
        auto provided =
            std::find_if(syntax.associated.begin(), syntax.associated.end(),
                         [&](const auto &candidate) {
                           return candidate.name == required.name;
                         });
        if (provided == syntax.associated.end()) {
          if (required.asyncFuture && required.defaultValue == Type::Unknown) {
            interfaces::AssociatedValue value;
            value.parameters = required.parameters;
            value.value = Type::Unknown;
            value.regions = required.regions;
            value.regionRequirements = required.regionRequirements;
            value.requirements = required.requirements;
            value.fromDefault = true;
            implementation.associated[item] = std::move(value);
            continue;
          }
          if (required.defaultValue == Type::Unknown) {
            error("type", syntax.span,
                  "missing associated item '" + required.name + "'");
            continue;
          }
          std::vector<TypeBinding> substitutions{
              {definition.self, implementation.target}};
          const auto &actual =
              checked.types->erased(implementation.interfaceType).arguments;
          for (std::size_t p = 0;
               p < actual.size() && p < definition.parameters.size(); ++p)
            substitutions.push_back({definition.parameters[p], actual[p]});
          implementation.associated[item] = {
              required.parameters,
              checked.types->substitute(required.defaultValue, substitutions),
              required.regions, required.regionRequirements};
          implementation.associated[item].fromDefault = true;
          continue;
        }
        if (provided->constant != required.constant)
          error("type", provided->span,
                "associated item kind does not match interface");
        auto family =
            makeGenericEnvironment(provided->genericParameters,
                                   provided->constraints, genericEnvironment);
        auto *outer = genericEnvironment;
        genericEnvironment = &family;
        auto outerRegions = regionEnvironment();
        auto outerRequirements = outerRegions.assumptions.size();
        auto familyRegions =
            pushRegionParameters(provided->genericParameters, provided->span);
        assumeRegionConstraints(provided->constraints, provided->span);
        interfaces::AssociatedValue value;
        value.regions = std::move(familyRegions);
        const auto &requirements = regionEnvironment().assumptions;
        value.regionRequirements.assign(
            requirements.begin() + outerRequirements, requirements.end());
        value.parameters.assign(family.parameters.begin() +
                                    implementation.parameters.size(),
                                family.parameters.end());
        value.requirements = interfaceAssumptions();
        value.value =
            required.constant
                ? provided->constantValue
                      ? constantType(
                            *provided->constantValue,
                            checked.types->parameter(required.parameter)
                                .valueType)
                      : Type::Unknown
            : !provided->value.empty()
                ? annotation(provided->value, provided->span)
                : Type::Unknown;
        if (value.value == Type::Unknown)
          error("type", provided->span,
                "associated item requires a definition");
        if (!required.constant && value.value != Type::Unknown) {
          if (checked.types->isSized(required.parameter) &&
              !checked.types->isSized(value.value))
            error("type", provided->span,
                  "associated type does not satisfy Sized");
          if (checked.types->isCopy(required.parameter) &&
              !checked.types->isCopy(value.value))
            error("type", provided->span,
                  "associated type does not satisfy Copy");
          if (checked.types->isUnpin(required.parameter) &&
              !unpinObligation(value.value, provided->span))
            error("type", provided->span,
                  "associated type does not satisfy Unpin");
        }
        if (value.parameters.size() != required.parameters.size())
          error("type", provided->span,
                "associated family parameter count does not match");
        if (value.regions.size() != required.regions.size())
          error("type", provided->span,
                "associated family region parameter count does not match");
        auto offered = outerRegions;
        offered.universe = regionEnvironment().universe;
        std::vector<RegionBinding> regionBindings;
        const auto &interface =
            checked.types->erased(implementation.interfaceType);
        for (std::size_t region = 0; region < definition.regions.size() &&
                                     region < interface.regionArguments.size();
             ++region)
          regionBindings.push_back(
              {definition.regions[region], interface.regionArguments[region]});
        for (std::size_t region = 0;
             region < required.regions.size() && region < value.regions.size();
             ++region)
          regionBindings.push_back(
              {required.regions[region], value.regions[region]});
        for (const auto &requirement : required.regionRequirements)
          offered.assumptions.push_back(
              {checked.types->regions().substitute(requirement.longer,
                                                   regionBindings),
               checked.types->regions().substitute(requirement.shorter,
                                                   regionBindings)});
        RegionSolver regionSolver(checked.types->regions());
        for (const auto &requirement : value.regionRequirements) {
          auto answer = regionSolver.outlives(requirement.longer,
                                              requirement.shorter, offered);
          if (answer != RegionAnswer::Proven)
            error(answer == RegionAnswer::Inconclusive ? "limit" : "region",
                  provided->span,
                  "associated family strengthens its declared outlives "
                  "requirements");
        }
        implementation.associated[item] = std::move(value);
        popRegionParameters();
        genericEnvironment = outer;
      }
      for (const auto &provided : syntax.associated)
        if (!syntax.shorthand &&
            std::none_of(
                definition.associated.begin(), definition.associated.end(),
                [&](const auto &item) { return item.name == provided.name; }))
          error("name", provided.span,
                "associated item is not declared by the interface");
      for (std::size_t method = 0; method < definition.methods.size();
           ++method) {
        const auto &required = definition.methods[method];
        std::optional<int> provided;
        for (std::size_t function = 0; function < module.functions.size();
             ++function) {
          const auto &candidate = module.functions[function];
          if ((candidate.implementation == static_cast<int>(i) ||
               std::find(syntax.methodFunctions.begin(),
                         syntax.methodFunctions.end(),
                         function) != syntax.methodFunctions.end()) &&
              candidate.name.ends_with("." + required.name)) {
            if (provided)
              error("name", candidate.span, "duplicate implementation method");
            provided = static_cast<int>(function);
          }
        }
        if (provided) {
          if (module.functions[*provided].asynchronous !=
              module.functions[required.function].asynchronous)
            error("type", module.functions[*provided].span,
                  "implementation method async modifier does not match "
                  "interface");
          implementation.methods[method] = {*provided,
                                            implementation.parameters, false};
          regionContracts.push_back(
              {static_cast<std::size_t>(*provided),
               static_cast<std::size_t>(required.function), syntax.span});
        } else if (module.functions[required.function].body.get()) {
          std::vector<Type> arguments{implementation.target};
          const auto &actual =
              checked.types->erased(implementation.interfaceType).arguments;
          arguments.insert(arguments.end(), actual.begin(), actual.end());
          implementation.methods[method] = {required.function,
                                            std::move(arguments), true};
        } else
          error("type", syntax.span,
                "missing interface method '" + required.name + "'");
      }
      for (std::size_t method = 0; method < definition.methods.size();
           ++method) {
        const auto &required = definition.methods[method];
        const auto &declaration = module.functions[required.function];
        if (!declaration.asynchronous)
          continue;
        auto associated = std::find_if(
            definition.associated.begin(), definition.associated.end(),
            [&](const auto &item) {
              return item.asyncFuture && item.name == declaration.asyncFuture;
            });
        auto binding = implementation.methods.find(method);
        if (associated == definition.associated.end() ||
            binding == implementation.methods.end() ||
            binding->second.defaultMethod ||
            !module.functions[binding->second.function].asynchronous)
          continue;

        const auto ordinal = static_cast<std::size_t>(
            associated - definition.associated.begin());
        const auto &provided = module.functions[binding->second.function];
        const auto &family = module.interfaces[interfaceDeclaration].associated;
        auto familySyntax =
            std::find_if(family.begin(), family.end(), [&](const auto &item) {
              return item.asyncFuture && item.name == declaration.asyncFuture;
            });
        if (familySyntax == family.end())
          continue;

        auto *outer = genericEnvironment;
        genericEnvironment = &functionGenerics.at(&provided);
        interfaces::AssociatedValue value;
        value.value =
            annotation(provided.annotation, provided.span, provided.owner);
        value.requirements = interfaceAssumptions();
        const auto &regions = functionRegions(provided);
        value.regionRequirements = regions.environment.assumptions;
        for (const auto &parameter : familySyntax->genericParameters) {
          if (parameter.kind == GenericParameterKind::Region) {
            if (auto region = regions.names.find(parameter.name);
                region != regions.names.end())
              value.regions.push_back(region->second);
          } else if (auto type = genericEnvironment->names.find(parameter.name);
                     type != genericEnvironment->names.end()) {
            value.parameters.push_back(type->second);
          }
        }
        if (value.parameters.size() != associated->parameters.size() ||
            value.regions.size() != associated->regions.size())
          error("type", provided.span,
                "async method future family parameters do not match");
        implementation.associated[ordinal] = std::move(value);
        genericEnvironment = outer;
      }
    } else if (syntax.interface.empty()) {
      for (std::size_t function = 0; function < module.functions.size();
           ++function) {
        const auto &method = module.functions[function];
        if (method.implementation != static_cast<int>(i) || method.constructor)
          continue;
        auto name = method.name.substr(method.name.rfind('.') + 1);
        if (!implementation.inherent
                 .emplace(name,
                          interfaces::MethodBinding{static_cast<int>(function),
                                                    implementation.parameters})
                 .second)
          error("name", method.span,
                "duplicate inherent implementation method");
      }
    }
    database.implementations.push_back(std::move(implementation));
    popRegionParameters();
  }
  genericEnvironment = saved;
  if (diagnostics.empty()) {
    interfaces::Solver solver(*checked.types, database, diagnostics);
    solver.coherent();
  }
  interfacesReady = true;
  if (diagnostics.empty())
    for (auto &requirement : projectionRequirements) {
      // Superinterfaces of interfaces still being declared were unknown when
      // the requirement was recorded.
      expandSuperinterfaces(requirement.assumptions);
      interfaces::Solver solver(*checked.types, database, diagnostics,
                                std::move(requirement.assumptions),
                                std::move(requirement.regions));
      if (!solver.prove({requirement.subject, requirement.interfaceType},
                        requirement.span, false))
        error("type", requirement.span,
              "associated projection requires its interface bound");
    }
  projectionRequirements.clear();
}

std::optional<std::size_t>
Checker::interfaceMethod(Type self, std::string_view name, Node &call) {
  std::vector<std::tuple<std::size_t, Type, int>> candidates;
  auto consider = [&](Type bound) {
    if (!checked.types->isErased(bound))
      return;
    for (auto inherited :
         interfaces::hierarchy(*checked.types, *checked.interfaceData, self,
                               bound, call.span, diagnostics)) {
      const auto descriptor = checked.types->erased(inherited);
      const auto &definition =
          checked.interfaceData->definitions[descriptor.declaration];
      for (std::size_t method = 0; method < definition.methods.size(); ++method)
        if (definition.methods[method].name == name)
          candidates.emplace_back(
              static_cast<std::size_t>(definition.methods[method].function),
              inherited, static_cast<int>(method));
    }
  };
  if (checked.types->isErased(self))
    consider(self);
  else if (checked.types->isProjection(self)) {
    interfaces::Solver solver(*checked.types, *checked.interfaceData,
                              diagnostics, interfaceAssumptions(),
                              regionEnvironment());
    for (const auto &bound : solver.projectionBounds(self, call.span))
      if (bound.property == interfaces::Property::Interface)
        consider(bound.interfaceType);
    for (const auto &bound : interfaceAssumptions())
      if (bound.subject == self &&
          bound.property == interfaces::Property::Interface)
        consider(bound.interfaceType);
  } else if (checked.types->isOpaque(self))
    for (auto bound : checked.types->product(self).opaqueBounds)
      consider(bound);
  else if (genericEnvironment && genericEnvironment->bounds.contains(self)) {
    for (const auto &bound : genericEnvironment->bounds.at(self))
      if (!propertyBound(bound, genericEnvironment->declarationSpan) &&
          bound.name != "unsized")
        consider(interfaceBound(bound, genericEnvironment->declarationSpan, {},
                                self));
  } else {
    interfaces::Solver solver(*checked.types, *checked.interfaceData,
                              diagnostics, interfaceAssumptions());
    for (const auto &implementation : checked.interfaceData->implementations) {
      auto bindings = solver.applicable(implementation, self, call.span);
      if (!bindings)
        continue;
      if (implementation.interfaceType == Type::Unknown) {
        auto method = implementation.inherent.find(std::string(name));
        if (method != implementation.inherent.end()) {
          facts(call).interfaceSelf = self;
          for (auto parameter : method->second.arguments)
            facts(call).implementationArguments.push_back(
                solver.normalize(parameter, *bindings, call.span));
          return static_cast<std::size_t>(method->second.function);
        }
        continue;
      }
      auto bound =
          checked.types->substitute(implementation.interfaceType, *bindings);
      if (solver.prove({self, bound}, call.span, false))
        consider(bound);
    }
  }
  std::sort(candidates.begin(), candidates.end());
  candidates.erase(std::unique(candidates.begin(), candidates.end()),
                   candidates.end());
  if (candidates.size() > 1) {
    error("type", call.span,
          "ambiguous interface method; use explicit disambiguation");
    return std::nullopt;
  }
  if (candidates.empty())
    return std::nullopt;
  auto [function, bound, method] = candidates[0];
  facts(call).interfaceSelf = self;
  facts(call).interfaceType = bound;
  facts(call).interfaceMethod = method;
  return function;
}

void Checker::checkInterfaceContracts() {
  auto *saved = genericEnvironment;
  for (const auto &implementation : checked.interfaceData->implementations) {
    if (!checked.types->isErased(implementation.interfaceType))
      continue;
    // Copied: interning substituted types below may grow the erased-type store.
    const auto descriptor = checked.types->erased(implementation.interfaceType);
    const auto &definition =
        checked.interfaceData->definitions[descriptor.declaration];
    for (const auto &[ordinal, provided] : implementation.associated) {
      const auto &required = definition.associated[ordinal];
      if (required.constant &&
          (!checked.types->isConstant(provided.value) ||
           checked.types->parameter(provided.value).valueType !=
               checked.types->parameter(required.parameter).valueType))
        error("type", implementation.span,
              "associated constant type does not match its declaration");
      std::vector<TypeBinding> bindings{
          {definition.self, implementation.target}};
      for (std::size_t p = 0;
           p < definition.parameters.size() && p < descriptor.arguments.size();
           ++p)
        bindings.push_back({definition.parameters[p], descriptor.arguments[p]});
      std::vector<TypeBinding> publicParameters;
      for (std::size_t p = 0;
           p < provided.parameters.size() && p < required.parameters.size();
           ++p)
        publicParameters.push_back(
            {provided.parameters[p], required.parameters[p]});
      auto allowed = implementation.requirements;
      allowed.push_back({implementation.target, implementation.interfaceType});
      for (auto obligation : required.requirements) {
        obligation.subject =
            checked.types->substitute(obligation.subject, bindings);
        obligation.interfaceType =
            checked.types->substitute(obligation.interfaceType, bindings);
        allowed.push_back(obligation);
      }
      interfaces::Solver associated(*checked.types, *checked.interfaceData,
                                    diagnostics, allowed);
      if (!(provided.fromDefault && required.asyncFutureDefaultInferred))
        for (auto obligation : provided.requirements) {
          obligation.subject =
              checked.types->substitute(obligation.subject, publicParameters);
          obligation.interfaceType = checked.types->substitute(
              obligation.interfaceType, publicParameters);
          if (!associated.prove(obligation, implementation.span, false))
            error("type", implementation.span,
                  "associated family strengthens its interface bounds");
        }
      auto value = checked.types->substitute(provided.value, publicParameters);
      if (!required.constant && checked.types->isSized(required.parameter) &&
          !checked.types->isSized(value))
        error("type", implementation.span,
              "associated item does not satisfy its Sized contract");
      bindings.push_back({required.parameter, value});
      std::vector<RegionBinding> familyRegions;
      for (std::size_t r = 0;
           r < provided.regions.size() && r < required.regions.size(); ++r)
        familyRegions.push_back({required.regions[r], provided.regions[r]});
      for (auto obligation : required.bounds) {
        obligation.subject =
            checked.types->substitute(obligation.subject, bindings);
        obligation.interfaceType =
            checked.types->substitute(obligation.interfaceType, bindings);
        obligation.interfaceType = checked.types->substituteRegions(
            obligation.interfaceType, familyRegions);
        if (!associated.prove(obligation, implementation.span, false))
          error("type", implementation.span,
                "associated item does not satisfy its interface bounds");
      }
      for (std::size_t p = 0;
           p < provided.parameters.size() && p < required.parameters.size();
           ++p)
        if ((checked.types->isCopy(provided.parameters[p]) &&
             !checked.types->isCopy(required.parameters[p])) ||
            (checked.types->isSized(provided.parameters[p]) &&
             !checked.types->isSized(required.parameters[p])))
          error("type", implementation.span,
                "associated family strengthens parameter capabilities");
    }
    for (const auto &[slot, binding] : implementation.methods) {
      if (binding.defaultMethod)
        continue;
      const auto &required = definition.methods[slot];
      const auto &declaration = module.functions[required.function];
      const auto &provided = module.functions[binding.function];
      genericEnvironment = &functionGenerics.at(&provided);
      const auto &regionScope = functionRegions(provided);
      interfaces::Solver solver(*checked.types, *checked.interfaceData,
                                diagnostics, interfaceAssumptions(),
                                regionScope.environment);
      const auto &expected = checked.functions[required.function];
      const auto &actual = checked.functions[binding.function];
      std::vector<TypeBinding> substitutions;
      std::vector<TypeBinding> ownerBindings;
      for (std::size_t p = 0; p < implementation.parameters.size() &&
                              p < actual.genericParameters.size();
           ++p)
        ownerBindings.push_back(
            {implementation.parameters[p], actual.genericParameters[p]});
      std::vector<RegionBinding> ownerRegions;
      std::size_t region = 0;
      if (provided.implementation >= 0)
        for (const auto &parameter :
             module.implementations[provided.implementation].genericParameters)
          if (parameter.kind == GenericParameterKind::Region &&
              region < implementation.regions.size()) {
            if (auto found = regionScope.names.find(parameter.name);
                found != regionScope.names.end())
              ownerRegions.push_back(
                  {implementation.regions[region], found->second});
            ++region;
          }
      if (!expected.genericParameters.empty())
        substitutions.push_back({expected.genericParameters[0],
                                 checked.types->substituteRegions(
                                     checked.types->substitute(
                                         implementation.target, ownerBindings),
                                     ownerRegions)});
      for (std::size_t p = 0; p < descriptor.arguments.size() &&
                              p + 1 < expected.genericParameters.size();
           ++p)
        substitutions.push_back(
            {expected.genericParameters[p + 1],
             checked.types->substituteRegions(
                 checked.types->substitute(descriptor.arguments[p],
                                           ownerBindings),
                 ownerRegions)});
      auto ownExpected =
          expected.genericParameters.size() >= required.implicitParameters
              ? expected.genericParameters.size() - required.implicitParameters
              : 0;
      auto ownActual =
          actual.genericParameters.size() >= implementation.parameters.size()
              ? actual.genericParameters.size() -
                    implementation.parameters.size()
              : 0;
      bool contractReported = false;
      auto fail = [&] {
        if (!std::exchange(contractReported, true))
          error("type", provided.span,
                "implementation method contract does not match interface");
      };
      if (!actual.targetFeatures.empty() &&
          !featuresAvailable(checked.targetDescription, expected.targetFeatures,
                             actual.targetFeatures))
        fail();
      if (ownExpected != ownActual)
        fail();
      for (std::size_t p = 0; p < ownExpected && p < ownActual; ++p)
        substitutions.push_back(
            {expected.genericParameters[required.implicitParameters + p],
             actual.genericParameters[implementation.parameters.size() + p]});
      std::vector<TypeBinding> publicBindings;
      if (!expected.genericParameters.empty())
        publicBindings.push_back(
            {expected.genericParameters[0], implementation.target});
      for (std::size_t p = 0; p < descriptor.arguments.size() &&
                              p + 1 < expected.genericParameters.size();
           ++p)
        publicBindings.push_back(
            {expected.genericParameters[p + 1], descriptor.arguments[p]});
      genericEnvironment = &functionGenerics.at(&declaration);
      auto allowed = interfaceAssumptions();
      for (auto &obligation : allowed) {
        obligation.subject =
            checked.types->substitute(obligation.subject, publicBindings);
        obligation.interfaceType =
            checked.types->substitute(obligation.interfaceType, publicBindings);
      }
      allowed.insert(allowed.end(), implementation.requirements.begin(),
                     implementation.requirements.end());
      genericEnvironment = &functionGenerics.at(&provided);
      auto requirements = interfaceAssumptions();
      std::vector<TypeBinding> publicParameters;
      for (std::size_t p = 0; p < ownerBindings.size(); ++p)
        publicParameters.push_back(
            {ownerBindings[p].argument, ownerBindings[p].parameter});
      for (std::size_t p = 0; p < ownExpected && p < ownActual; ++p)
        publicParameters.push_back(
            {actual.genericParameters[implementation.parameters.size() + p],
             expected.genericParameters[required.implicitParameters + p]});
      interfaces::Solver contracts(*checked.types, *checked.interfaceData,
                                   diagnostics, allowed);
      for (auto obligation : requirements) {
        obligation.subject =
            checked.types->substitute(obligation.subject, publicParameters);
        obligation.interfaceType = checked.types->substitute(
            obligation.interfaceType, publicParameters);
        if (!contracts.prove(obligation, provided.span, false) &&
            !std::exchange(contractReported, true))
          error("type", provided.span,
                "implementation method strengthens its interface bounds");
      }
      for (std::size_t p = 0; p < ownExpected && p < ownActual; ++p)
        if (checked.types->isSized(
                actual
                    .genericParameters[implementation.parameters.size() + p]) &&
            !checked.types->isSized(
                expected.genericParameters[required.implicitParameters + p]) &&
            !std::exchange(contractReported, true))
          error("type", provided.span,
                "implementation method strengthens Sized requirements");
      for (auto &contract : regionContracts)
        if (contract.implementation ==
                static_cast<std::size_t>(binding.function) &&
            contract.declaration == static_cast<std::size_t>(required.function))
          contract.bindings = substitutions;
      if (declaration.parameters.size() != provided.parameters.size()) {
        fail();
        continue;
      }
      auto shape = [&](Type type, std::span<const TypeBinding> bindings) {
        return checked.types->eraseRegions(
            solver.normalize(type, bindings, provided.span));
      };
      for (std::size_t parameter = 0; parameter < provided.parameters.size();
           ++parameter)
        if (shape(expected.locals[parameter].type, substitutions) !=
                shape(actual.locals[parameter].type, {}) ||
            expected.locals[parameter].mode != actual.locals[parameter].mode ||
            declaration.parameters[parameter].format !=
                provided.parameters[parameter].format)
          fail();
      if (shape(expected.result, substitutions) != shape(actual.result, {}) ||
          shape(expected.error, substitutions) != shape(actual.error, {}))
        fail();
    }
  }
  genericEnvironment = saved;
}

void Checker::finalizeInterfaces() {
  for (auto &definition : checked.interfaceData->definitions)
    for (auto &method : definition.methods) {
      const auto &function = module.functions[method.function];
      const auto &facts = checked.functions[method.function];
      method.signature.parameters.clear();
      for (std::size_t p = 0; p < function.parameters.size(); ++p)
        method.signature.parameters.push_back(
            {facts.locals[p].type, facts.locals[p].mode});
      method.signature.result = facts.result;
      method.signature.error = facts.error;
      method.signature.abiResult = facts.abiResult;
      method.signature.resultSources = facts.resultSources;
      method.signature.targetFeatures = facts.targetFeatures;
      method.signature.mode = function.receiver == "mut" ? ParameterMode::Mut
                              : function.receiver == "take"
                                  ? ParameterMode::Take
                                  : ParameterMode::Read;
    }
  finalizeErasure();
}

std::optional<Type> Checker::associatedConstant(const Node &node) {
  if (node.kind == Kind::Name && node.annotation.form == TypeForm::Projection &&
      node.annotation.elements.size() == 2) {
    auto subject = annotation(node.annotation.elements[0], node.span);
    auto interface =
        interfaceBound(node.annotation.elements[1], node.span, {}, subject);
    return interfaceProjection(subject, interface, node.annotation.name,
                               node.genericArguments, node.span);
  }
  if (node.kind != Kind::Name)
    return std::nullopt;
  if (node.text.find("::") == std::string::npos) {
    auto canonical =
        checked.symbols->lookup(checked.symbols->moduleOf(node.span), node.text,
                                resolution::Namespace::Value, node.span);
    auto resolved = canonical ? inherentConstantNames.find(*canonical)
                              : inherentConstantNames.end();
    return resolved == inherentConstantNames.end()
               ? std::nullopt
               : inherentConstantValue(
                     resolved->second,
                     inherentConstants[resolved->second].target);
  }

  auto delimiter = node.text.rfind("::");
  auto prefix = node.text.substr(0, delimiter);
  auto member = node.text.substr(delimiter + 2);
  Type subject = Type::Unknown;
  auto owner = current ? current->owner : std::string_view{};
  if (genericEnvironment) {
    auto parameter = genericEnvironment->names.find(prefix);
    if (parameter != genericEnvironment->names.end() &&
        !checked.types->isConstant(parameter->second))
      subject = parameter->second;
  }
  // Only annotate the prefix when some inherent constant has this member;
  // otherwise a qualified variant would report missing generic arguments.
  bool memberDeclared = false;
  for (const auto &[name, index] : inherentConstantNames)
    if (name.size() > member.size() + 2 && name.ends_with(member) &&
        name.compare(name.size() - member.size() - 2, 2, "::") == 0) {
      memberDeclared = true;
      break;
    }
  if (subject == Type::Unknown && memberDeclared) {
    auto canonicalType = typeName(prefix, node.span, owner);
    if (!canonicalType.empty()) {
      TypeSyntax syntax;
      syntax.name = prefix;
      syntax.arguments = node.ownerGenericArguments;
      subject = annotation(syntax, node.span, owner);
    }
  }
  if (auto builtin = builtinType(prefix);
      builtin != Type::Unknown &&
      (subject == Type::Unknown || subject == builtin))
    if (auto found = inherentConstantNames.find(prefix + "::" + member);
        found != inherentConstantNames.end())
      return inherentConstantValue(found->second, builtin);
  if (checked.types->isProduct(subject)) {
    auto ownerType = subject;
    if (checked.types->product(ownerType).genericOrigin != Type::Unknown)
      ownerType = checked.types->product(ownerType).genericOrigin;
    auto key = checked.types->product(ownerType).name + "::" + member;
    auto candidate = inherentConstantNames.find(key);
    auto lookupName = prefix == "Self" ? key : node.text;
    auto canonical = checked.symbols->lookup(
        checked.symbols->moduleOf(node.span), lookupName,
        resolution::Namespace::Value, node.span);
    auto resolved = canonical ? inherentConstantNames.find(*canonical)
                              : inherentConstantNames.end();
    if (resolved != inherentConstantNames.end())
      return inherentConstantValue(resolved->second, subject);
    if (candidate != inherentConstantNames.end()) {
      error("name", node.span,
            "unresolved or inaccessible name '" + displayPath(lookupName) +
                "'");
      return std::nullopt;
    }
  }

  TypeSyntax syntax;
  syntax.name = node.text;
  auto type = interfaceAnnotation(
      syntax, node.span, current ? current->owner : std::string_view{});
  if (type && checked.types->isConstant(*type))
    return *type;
  return std::nullopt;
}
} // namespace mettle
