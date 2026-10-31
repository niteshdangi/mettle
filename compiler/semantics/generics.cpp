#include "semantics/checker.h"
#include "support/limits.h"
#include "support/path.h"
#include "syntax/lexer.h"
#include <algorithm>
#include <charconv>
#include <stdexcept>

namespace mettle {
Checker::GenericEnvironment Checker::makeGenericEnvironment(
    const std::vector<GenericParameter> &parameters,
    const std::vector<GenericConstraint> &constraints,
    const GenericEnvironment *parent) {
  GenericEnvironment result = parent ? *parent : GenericEnvironment{};
  if (!parameters.empty())
    result.declarationSpan = parameters.front().span;
  else if (!constraints.empty())
    result.declarationSpan = constraints.front().span;
  auto saved = genericEnvironment;
  genericEnvironment = &result;
  for (const auto &parameter : parameters) {
    if (parameter.kind == GenericParameterKind::Region)
      continue;
    if (result.names.contains(parameter.name)) {
      error("name", parameter.span,
            "duplicate generic parameter '" + parameter.name + "'");
      continue;
    }
    bool copy = false, sized = true, requiredSized = false, unpin = false;
    for (const auto &bound : parameter.bounds) {
      copy |= interfaceProperty(bound, "Copy", parameter.span);
      unpin |= interfaceProperty(bound, "Unpin", parameter.span);
      requiredSized |= interfaceProperty(bound, "Sized", parameter.span);
      if (bound.name == "?Sized" || bound.name == "unsized")
        sized = false;
    }
    for (const auto &constraint : constraints)
      if (!constraint.region && constraint.subject.name == parameter.name)
        for (const auto &bound : constraint.bounds) {
          copy |= interfaceProperty(bound, "Copy", parameter.span);
          unpin |= interfaceProperty(bound, "Unpin", parameter.span);
          requiredSized |= interfaceProperty(bound, "Sized", parameter.span);
          if (bound.name == "?Sized" || bound.name == "unsized")
            sized = false;
        }
    sized |= requiredSized;
    Type type;
    if (parameter.kind == GenericParameterKind::Const) {
      auto valueType = annotation(parameter.annotation, parameter.span);
      if (!isInteger(valueType) && valueType != Type::Bool &&
          valueType != Type::Char)
        error("type", parameter.span,
              "const parameter requires a supported scalar type");
      type = checked.types->declareConstParameter(parameter.name, valueType);
    } else
      type = checked.types->declareParameter(parameter.name, copy, sized);
    if (unpin && parameter.kind == GenericParameterKind::Type)
      checked.types->constrainUnpin(type);
    result.names.emplace(parameter.name, type);
    result.parameters.push_back(type);
    result.bounds[type] = parameter.bounds;
  }
  for (const auto &constraint : constraints) {
    if (constraint.region)
      continue;
    auto found = result.names.find(constraint.subject.name);
    if (found != result.names.end()) {
      result.bounds[found->second].insert(result.bounds[found->second].end(),
                                          constraint.bounds.begin(),
                                          constraint.bounds.end());
      result.boundConstraints.insert(&constraint);
    }
  }
  genericEnvironment = saved;
  return result;
}
void Checker::prepareGenerics() {
  for (const auto &product : module.products) {
    auto environment =
        makeGenericEnvironment(product.genericParameters, product.constraints);
    environment.declarationSpan = product.span;
    auto type = typeNames.at(definitionName(product.span, product.name));
    checked.types->setGenericParameters(type, environment.parameters);
    productGenerics.emplace(&product, std::move(environment));
  }
  for (const auto &alias : module.aliases) {
    auto environment =
        makeGenericEnvironment(alias.genericParameters, alias.constraints);
    environment.declarationSpan = alias.span;
    aliasGenerics.emplace(&alias, std::move(environment));
  }
  for (std::size_t i = 0; i < module.interfaces.size(); ++i) {
    const auto &interface = module.interfaces[i];
    GenericEnvironment parent;
    parent.names["Self"] = checked.interfaceData->definitions[i].self;
    auto environment = makeGenericEnvironment(interface.genericParameters,
                                              interface.constraints, &parent);
    environment.declarationSpan = interface.span;
    checked.interfaceData->definitions[i].parameters = environment.parameters;
    interfaceGenerics.emplace(&interface, std::move(environment));
  }
  for (const auto &product : module.products)
    validateGenericEnvironment(product.genericParameters, product.constraints,
                               productGenerics.at(&product));
  for (const auto &alias : module.aliases)
    validateGenericEnvironment(alias.genericParameters, alias.constraints,
                               aliasGenerics.at(&alias));
  for (const auto &interface : module.interfaces)
    if (std::none_of(interface.genericParameters.begin(),
                     interface.genericParameters.end(),
                     [](const auto &parameter) {
                       return parameter.kind == GenericParameterKind::Region;
                     }))
      validateGenericEnvironment(interface.genericParameters,
                                 interface.constraints,
                                 interfaceGenerics.at(&interface));
  for (auto &function : module.functions) {
    const GenericEnvironment *parent = nullptr;
    if (!function.owner.empty() && function.implementation < 0) {
      auto name = typeName(function.owner, function.span);
      if (const auto &named = productsNamed(name); !named.empty())
        parent = &productGenerics.at(named.front());
    }
    auto environment = makeGenericEnvironment(function.genericParameters,
                                              function.constraints, parent);
    environment.declarationSpan = function.span;
    functionGenerics.emplace(&function, std::move(environment));
  }
  for (auto &function : module.functions) {
    if (function.implementation >= 0) {
      auto saved = genericEnvironment;
      genericEnvironment = &functionGenerics.at(&function);
      const auto &implementation =
          module.implementations[function.implementation];
      genericEnvironment->names["Self"] =
          annotation(implementation.target, function.span);
      genericEnvironment = saved;
    }
    validateGenericEnvironment(function.genericParameters, function.constraints,
                               functionGenerics.at(&function));
  }
}
void Checker::validateGenericEnvironment(
    const std::vector<GenericParameter> &parameters,
    const std::vector<GenericConstraint> &constraints,
    GenericEnvironment &environment) {
  auto saved = genericEnvironment;
  genericEnvironment = &environment;
  for (const auto &constraint : constraints) {
    if (constraint.region || constraint.bounds.empty() ||
        !environment.boundConstraints.insert(&constraint).second)
      continue;
    auto found = environment.names.find(constraint.subject.name);
    auto subject = found == environment.names.end()
                       ? annotation(constraint.subject, constraint.span)
                       : found->second;
    auto &bounds = environment.bounds[subject];
    bounds.insert(bounds.end(), constraint.bounds.begin(),
                  constraint.bounds.end());
  }
  for (const auto &[subject, bounds] : environment.bounds)
    for (const auto &bound : bounds) {
      if (bound.form == TypeForm::Callable) {
        auto contract =
            callableAnnotation(bound, environment.declarationSpan, {});
        std::vector<std::size_t> local;
        const auto &declared = bound.callable->parameters;
        const auto &formal = checked.types->callable(contract).parameters;
        for (std::size_t p = 0; p < declared.size() && p < formal.size(); ++p)
          if (declared[p].annotation.sources.empty() &&
              (formal[p].mode == ParameterMode::Read ||
               formal[p].mode == ParameterMode::Mut))
            local.push_back(p);
        if (!checked.types->constrainCallableParameter(subject, contract,
                                                       std::move(local)))
          error("type", environment.declarationSpan,
                "incompatible declared callable bounds");
      } else if (!propertyBound(bound, environment.declarationSpan) &&
                 bound.name != "unsized" && bound.name != "?Sized")
        interfaceBound(bound, environment.declarationSpan, {}, subject);
    }
  for (const auto &constraint : constraints) {
    if (!constraint.equality)
      continue;
    auto found = environment.names.find(constraint.subject.name);
    auto left = found == environment.names.end()
                    ? annotation(constraint.subject, constraint.span)
                    : found->second;
    auto right = annotation(*constraint.equality, constraint.span);
    auto dependencies = checked.types->typeParameters(right);
    if (left != right && std::find(dependencies.begin(), dependencies.end(),
                                   left) != dependencies.end()) {
      error("type", constraint.span, "recursive generic type equality");
      continue;
    }
    environment.equalities.push_back({left, right});
    if (checked.types->isParameter(left) && checked.types->isParameter(right)) {
      auto a = checked.types->parameter(left),
           b = checked.types->parameter(right);
      checked.types->constrainParameter(
          left, a.copyRequested || b.copyRequested, a.sized || b.sized);
      checked.types->constrainParameter(
          right, a.copyRequested || b.copyRequested, a.sized || b.sized);
      auto &target = environment.bounds[right];
      const auto &source = environment.bounds[left];
      target.insert(target.end(), source.begin(), source.end());
    }
    if (found != environment.names.end() && left != right)
      found->second = right;
  }
  for (const auto &parameter : parameters) {
    if (parameter.kind == GenericParameterKind::Region)
      continue;
    auto found = std::find_if(
        environment.parameters.begin(), environment.parameters.end(),
        [&](Type type) { return checked.types->name(type) == parameter.name; });
    if (found == environment.parameters.end())
      continue;
    Type value = Type::Unknown;
    if (!parameter.defaultType.empty())
      value = annotation(parameter.defaultType, parameter.span);
    else if (parameter.defaultValue) {
      GenericArgument argument;
      argument.value = parameter.defaultValue;
      argument.span = parameter.span;
      value = genericArgument(argument, *found);
    } else
      continue;
    environment.defaults.emplace(*found, value);
    auto dependencies = checked.types->typeParameters(value);
    auto self = environment.names.find("Self");
    bool dependsOnSelf = self != environment.names.end() &&
                         std::find(dependencies.begin(), dependencies.end(),
                                   self->second) != dependencies.end();
    if (!dependsOnSelf)
      deferredObligations.push_back({&environment,
                                     &environment,
                                     {TypeBinding{*found, value}},
                                     {*found},
                                     parameter.span});
  }
  genericEnvironment = saved;
}
void Checker::proveDeferredObligations() {
  implementationsRegistered = true;
  auto saved = genericEnvironment;
  auto pending = std::move(deferredObligations);
  deferredObligations.clear();
  for (const auto &item : pending) {
    genericEnvironment = item.context;
    obligationParameters = &item.parameters;
    obligationsOnly = true;
    genericObligations(*item.environment, item.bindings, item.span);
    obligationParameters = nullptr;
    obligationsOnly = false;
  }
  genericEnvironment = saved;
}
void Checker::propagateGenericBindings(const GenericEnvironment &environment,
                                       std::vector<TypeBinding> &bindings,
                                       Span span) {
  auto solve = [&](Type left, Type right) {
    bool unresolved = false;
    for (const auto &binding : bindings)
      unresolved |=
          binding.parameter == right && binding.argument == Type::Unknown;
    for (auto &binding : bindings)
      if (binding.parameter == left && binding.argument == Type::Unknown &&
          right != Type::Unknown && !unresolved) {
        binding.argument = right;
        return true;
      }
    return false;
  };
  // `I: Iterator<Item = T>` determines `T` once `I` is known: normalize the
  // projection `I::Item` and bind `T` to it.
  auto fromBounds = [&] {
    bool progress = false;
    for (const auto &[subject, bounds] : environment.bounds) {
      auto owner = std::find_if(bindings.begin(), bindings.end(),
                                [&](const auto &binding) {
                                  return binding.parameter == subject &&
                                         binding.argument != Type::Unknown;
                                });
      if (owner == bindings.end())
        continue;
      for (const auto &bound : bounds)
        for (const auto &argument : bound.arguments) {
          if (argument.binding.empty() || !argument.type ||
              argument.type->form != TypeForm::Named)
            continue;
          auto target = environment.names.find(argument.type->name);
          if (target == environment.names.end())
            continue;
          auto open = std::find_if(
              bindings.begin(), bindings.end(), [&](const auto &binding) {
                return binding.parameter == target->second &&
                       binding.argument == Type::Unknown;
              });
          if (open == bindings.end())
            continue;
          auto stripped = bound;
          stripped.arguments.erase(
              std::remove_if(
                  stripped.arguments.begin(), stripped.arguments.end(),
                  [](const auto &item) { return !item.binding.empty(); }),
              stripped.arguments.end());
          auto savedEnvironment = genericEnvironment;
          genericEnvironment = const_cast<GenericEnvironment *>(&environment);
          auto interfaceType = interfaceBound(
              stripped, environment.declarationSpan, {}, owner->argument);
          genericEnvironment = savedEnvironment;
          if (interfaceType == Type::Unknown)
            continue;
          auto value = interfaceProjection(owner->argument, interfaceType,
                                           argument.binding, {}, span);
          if (value == Type::Unknown ||
              std::any_of(bindings.begin(), bindings.end(),
                          [&](const auto &binding) {
                            return binding.parameter == value;
                          }))
            continue;
          open->argument = value;
          progress = true;
        }
    }
    return progress;
  };
  bool changed;
  do {
    changed = fromBounds();
    for (const auto &equality : environment.equalities) {
      auto left = checked.types->substitute(equality.parameter, bindings);
      auto right = checked.types->substitute(equality.argument, bindings);
      changed |= solve(equality.parameter, right);
      changed |= solve(equality.argument, left);
    }
  } while (changed);
}
void Checker::completeGenericBindings(const GenericEnvironment &environment,
                                      std::vector<TypeBinding> &bindings,
                                      Span span) {
  propagateGenericBindings(environment, bindings, span);
  for (auto &binding : bindings)
    if (binding.argument == Type::Unknown)
      if (auto found = environment.defaults.find(binding.parameter);
          found != environment.defaults.end())
        binding.argument = checked.types->substitute(found->second, bindings);
  auto saved = genericEnvironment;
  if (auto caller = functionGenerics.find(current);
      caller != functionGenerics.end())
    genericEnvironment = &caller->second;
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (genericEnvironment && genericEnvironment != &environment)
    solver.setEqualities(genericEnvironment->equalities);
  genericEnvironment = saved;
  for (const auto &equality : environment.equalities) {
    auto left = solver.normalize(equality.parameter, bindings, span);
    auto right = solver.normalize(equality.argument, bindings, span);
    if (left != Type::Unknown && right != Type::Unknown && left != right)
      error("type", span, "generic type equality is not satisfied");
  }
}
const std::vector<Type> &Checker::genericBindings(Function &function) {
  genericEnvironment = &functionGenerics.at(&function);
  return genericEnvironment->parameters;
}
Type Checker::constantContext(const Node &node) {
  if (node.kind == Kind::Binary && (node.text == "<<" || node.text == ">>"))
    return constantContext(*node.children[0]);
  if (node.kind == Kind::Integer)
    return literal(node);
  if (node.kind == Kind::Name) {
    if (auto storage = staticName(node.text, node.span))
      return checked.staticStorage[*storage].type;
    if (auto primitive = machineValue(node))
      if (facts(node).numeric && isInteger(inference.value(*primitive)))
        return inference.value(*primitive);
    if (node.text.find("::") != std::string::npos)
      if (auto associated = associatedConstant(node))
        return checked.types->parameter(*associated).valueType;
    if (genericEnvironment) {
      auto found = genericEnvironment->names.find(node.text);
      if (found != genericEnvironment->names.end() &&
          checked.types->isConstant(found->second))
        return checked.types->parameter(found->second).valueType;
    }
  }
  for (const auto &child : node.children) {
    auto context = constantContext(*child);
    if (context != Type::Unknown)
      return context;
  }
  return Type::Unknown;
}
static bool containsField(const Node &node) {
  if (node.kind == Kind::Field && !node.flag)
    return true;
  return std::any_of(
      node.children.begin(), node.children.end(),
      [](const NodeOwner &child) { return containsField(*child); });
}
Type Checker::constantType(const Node &node, Type expected) {
  // Dotted paths (`Mod.N`, `Type.N`) in associated-constant values, array
  // lengths, constant arguments and discriminants qualify like other paths.
  // The nodes are parser-owned and qualification is idempotent.
  if (containsField(node))
    qualifyDottedPaths(const_cast<Node &>(node));
  if (needsEvaluator(node))
    return evaluatedConstant(node, expected);
  if (node.kind == Kind::Name)
    if (auto primitive = machineValue(node))
      if (facts(node).numeric && isInteger(inference.value(*primitive))) {
        facts(node).type = inference.value(*primitive);
        return checked.types->constant(facts(node).type, *facts(node).numeric);
      }
  if (node.kind == Kind::Name)
    if (auto storage = staticName(node.text, node.span)) {
      if (module.statics[*storage].mutableBinding) {
        error("constant", node.span,
              "required initialization cannot read mutable storage");
        return Type::Unknown;
      }
      auto value = staticValue(*storage);
      if (!value)
        return Type::Unknown;
      if (value->kind != StaticConstant::Kind::Scalar ||
          (!isInteger(value->type) && value->type != Type::Bool &&
           value->type != Type::Char)) {
        error("constant", node.span,
              "required integer expression needs scalar integer storage");
        return Type::Unknown;
      }
      return checked.types->constant(value->type, value->scalar);
    }
  if (node.kind == Kind::Name &&
      (node.annotation.form == TypeForm::Projection ||
       node.text.find("::") != std::string::npos)) {
    auto errorsBefore = reportedErrors;
    if (auto associated = associatedConstant(node))
      return *associated;
    if (reportedErrors != errorsBefore)
      return Type::Unknown;
  }
  if (node.kind == Kind::Name && genericEnvironment) {
    auto found = genericEnvironment->names.find(node.text);
    if (found != genericEnvironment->names.end() &&
        checked.types->isConstant(found->second))
      return found->second;
  }
  if (node.kind == Kind::Name && node.text.find("::") == std::string::npos) {
    auto errorsBefore = reportedErrors;
    if (auto associated = associatedConstant(node))
      return *associated;
    if (reportedErrors != errorsBefore)
      return Type::Unknown;
  }
  if (node.kind == Kind::Group)
    return constantType(*node.children[0], expected);
  if (node.kind == Kind::Boolean)
    return checked.types->constant(Type::Bool, node.text == "true");
  if (node.kind == Kind::Character) {
    auto value = characterLiteral(node.text, node.flag, diagnostics, node.span);
    return value ? checked.types->constant(node.flag ? Type::U8 : Type::Char,
                                           *value)
                 : Type::Unknown;
  }
  if (node.kind == Kind::Integer ||
      (node.kind == Kind::Unary && node.text == "-" &&
       node.children[0]->kind == Kind::Integer)) {
    bool negative = node.kind == Kind::Unary;
    const auto &syntax = negative ? *node.children[0] : node;
    auto suffix = literal(syntax, negative);
    auto type = suffix != Type::Unknown ? suffix
                : isInteger(expected)   ? expected
                                        : Type::I32;
    if (!facts(syntax).numeric ||
        !integerLiteralFits(*facts(syntax).numeric, type, pointerBits())) {
      error("type", node.span,
            "required integer constant is outside the " +
                displayPath(checked.types->name(type)) + " range");
      return Type::Unknown;
    }
    facts(syntax).type = type;
    return checked.types->constant(type, *facts(syntax).numeric);
  }
  if (node.kind == Kind::Binary) {
    bool shift = node.text == "<<" || node.text == ">>";
    auto context = constantContext(node);
    if (context == Type::Unknown)
      context = expected;
    auto left = constantType(*node.children[0], context);
    auto right =
        constantType(*node.children[1], shift ? Type::Unknown : context);
    if (left == Type::Unknown || right == Type::Unknown)
      return Type::Unknown;
    try {
      return checked.types->constantExpression(node.text, {left, right});
    } catch (const std::invalid_argument &failure) {
      error("type", node.span, failure.what());
      return Type::Unknown;
    }
  }
  if (node.kind == Kind::Unary && node.text == "-") {
    auto operand = constantType(*node.children[0], expected);
    if (operand == Type::Unknown)
      return operand;
    try {
      return checked.types->constantExpression(
          "-", {checked.types->constant(
                    checked.types->parameter(operand).valueType, 0),
                operand});
    } catch (const std::invalid_argument &failure) {
      error("type", node.span, failure.what());
      return Type::Unknown;
    }
  }
  if (node.kind == Kind::Unary && node.text == "!") {
    auto operand = constantType(*node.children[0], expected);
    if (operand == Type::Unknown)
      return operand;
    auto valueType = checked.types->parameter(operand).valueType;
    try {
      return checked.types->constantExpression(
          valueType == Type::Bool ? "==" : "^",
          {operand,
           checked.types->constant(
               valueType, valueType == Type::Bool ? integerLiteral(0)
                          : isSignedInteger(valueType)
                              ? integerLiteral(-1)
                              : integerMaximum(valueType, pointerBits()))});
    } catch (const std::invalid_argument &failure) {
      error("type", node.span, failure.what());
      return Type::Unknown;
    }
  }
  error("type", node.span,
        "unsupported operation in required constant integer/scalar expression");
  return Type::Unknown;
}
std::vector<Type>
Checker::genericArguments(const std::vector<GenericParameter> &parameters,
                          const std::vector<GenericArgument> &arguments,
                          GenericEnvironment &environment, Span span) {
  std::vector<Type> result;
  std::vector<TypeBinding> bindings;
  std::size_t argumentIndex = 0, parameterIndex = 0;
  for (const auto &parameter : parameters) {
    if (parameter.kind == GenericParameterKind::Region) {
      if (argumentIndex < arguments.size() &&
          !arguments[argumentIndex].region.empty())
        ++argumentIndex;
      continue;
    }
    auto identity = environment.parameters.at(parameterIndex++);
    auto value = argumentIndex < arguments.size()
                     ? genericArgument(arguments[argumentIndex++], identity)
                     : Type::Unknown;
    bindings.push_back({identity, value});
  }
  if (argumentIndex != arguments.size())
    error("type", span, "excess generic arguments");
  completeGenericBindings(environment, bindings, span);
  for (const auto &binding : bindings) {
    if (binding.argument == Type::Unknown)
      error("type", span,
            "missing generic argument '" +
                displayPath(checked.types->name(binding.parameter)) + "'");
    result.push_back(binding.argument);
  }
  std::vector<Type> concrete;
  if (!implementationsRegistered)
    for (const auto &binding : bindings)
      if (binding.argument != Type::Unknown &&
          checked.types->typeParameters(binding.argument).empty())
        concrete.push_back(binding.parameter);
  if (!concrete.empty()) {
    obligationParameters = &concrete;
    genericObligations(environment, bindings, span);
    obligationParameters = nullptr;
    deferredObligations.push_back(
        {&environment, nullptr, bindings, concrete, span});
  } else
    genericObligations(environment, bindings, span);
  return result;
}
bool Checker::genericObligations(const GenericEnvironment &environment,
                                 std::span<const TypeBinding> bindings,
                                 Span span,
                                 std::span<const RegionBinding> regions) {
  bool valid = true;
  auto caller = genericEnvironment;
  for (const auto &binding : bindings) {
    if (binding.argument == Type::Unknown) {
      valid = false;
      continue;
    }
    if (obligationParameters) {
      bool listed =
          std::find(obligationParameters->begin(), obligationParameters->end(),
                    binding.parameter) != obligationParameters->end();
      if (listed != obligationsOnly)
        continue;
    }
    if (checked.types->isConstant(binding.parameter)) {
      if (!checked.types->isConstant(binding.argument) ||
          checked.types->parameter(binding.parameter).valueType !=
              checked.types->parameter(binding.argument).valueType) {
        error("type", span, "const argument does not match its declared type");
        valid = false;
      }
      continue;
    }
    if (!checked.types->isParameter(binding.parameter))
      continue;
    const auto &parameter = checked.types->parameter(binding.parameter);
    if (parameter.copyRequested && !checked.types->isCopy(binding.argument)) {
      error("type", span, "generic argument does not satisfy Copy");
      valid = false;
    }
    if (parameter.sized && !checked.types->isSized(binding.argument)) {
      error("type", span, "generic argument does not satisfy Sized");
      valid = false;
    }
    if (parameter.unpin && !unpinObligation(binding.argument, span)) {
      error("type", span, "generic argument does not satisfy Unpin");
      valid = false;
    }
    auto found = environment.bounds.find(binding.parameter);
    if (found == environment.bounds.end())
      continue;
    for (const auto &bound : found->second)
      if (auto property = propertyBound(bound, environment.declarationSpan);
          property && (*property == interfaces::Property::Transferable ||
                       *property == interfaces::Property::Shareable ||
                       *property == interfaces::Property::Static)) {
        valid &= interfaceObligation(binding.argument, bound, span);
      } else if (!property && bound.name != "?Sized" &&
                 bound.name != "unsized") {
        genericEnvironment = const_cast<GenericEnvironment *>(&environment);
        if (bound.form == TypeForm::Callable) {
          auto contract =
              callableAnnotation(bound, environment.declarationSpan, {});
          auto required = normalizeGenericType(contract, bindings, span);
          genericEnvironment = caller;
          valid &= callableObligation(binding.argument, required, span);
          continue;
        }
        auto required = checked.types->substitute(
            interfaceBound(bound, environment.declarationSpan, {},
                           binding.parameter),
            bindings);
        required = checked.types->substituteRegions(required, regions);
        genericEnvironment = caller;
        required = normalizeGenericType(required, {}, span);
        valid &= interfaceObligation(binding.argument, required, span);
      }
  }
  genericEnvironment = caller;
  auto saved = genericEnvironment;
  genericEnvironment = const_cast<GenericEnvironment *>(&environment);
  auto requirements = interfaceAssumptions();
  genericEnvironment = saved;
  interfaces::Solver solver(*checked.types, *checked.interfaceData, diagnostics,
                            interfaceAssumptions(), regionEnvironment());
  if (genericEnvironment)
    solver.setEqualities(genericEnvironment->equalities);
  for (auto requirement : requirements) {
    if (requirement.property != interfaces::Property::Unpin)
      continue;
    requirement.subject =
        checked.types->substitute(requirement.subject, bindings);
    requirement.subject =
        checked.types->substituteRegions(requirement.subject, regions);
    if (!solver.prove(requirement, span, false)) {
      error("type", span, "unsatisfied Unpin requirement");
      valid = false;
    }
  }
  return valid;
}
std::optional<Type> Checker::genericAnnotation(const TypeSyntax &syntax,
                                               Span span,
                                               std::string_view owner) {
  if (syntax.form != TypeForm::Named || syntax.nested)
    return std::nullopt;
  if (genericEnvironment) {
    auto found = genericEnvironment->names.find(syntax.name);
    if (found != genericEnvironment->names.end()) {
      if (!syntax.arguments.empty())
        error("type", span, "generic parameter cannot take type arguments");
      if (checked.types->isConstant(found->second)) {
        error("type", span, "const parameter is not a type");
        return Type::Unknown;
      }
      return syntax.view.empty() ? found->second
                                 : checked.types->viewType(
                                       found->second, syntax.view == "read"
                                                          ? ParameterMode::Read
                                                          : ParameterMode::Mut);
    }
  }
  auto name = typeName(syntax.name, span, owner);
  for (const auto *candidate : productsNamed(name))
    if (const auto &product = *candidate;
        !productGenerics.at(&product).parameters.empty()) {
      if (++genericDepth > limits::typeDepth) {
        --genericDepth;
        error("limit", span, "generic type expansion limit exceeded");
        return Type::Unknown;
      }
      auto argumentSyntax = syntax.arguments;
      if (syntax.name == "Self" && argumentSyntax.empty() && genericEnvironment)
        for (const auto &parameter : product.genericParameters) {
          if (parameter.kind == GenericParameterKind::Region)
            continue;
          GenericArgument argument;
          TypeSyntax source;
          source.name = parameter.name;
          argument.type = std::make_shared<const TypeSyntax>(std::move(source));
          argument.span = span;
          argumentSyntax.push_back(std::move(argument));
        }
      auto arguments =
          genericArguments(product.genericParameters, argumentSyntax,
                           productGenerics.at(&product), span);
      auto result = checked.types->instantiateProduct(typeNames.at(name),
                                                      std::move(arguments));
      --genericDepth;
      if (!syntax.view.empty())
        result = checked.types->viewType(result, syntax.view == "read"
                                                     ? ParameterMode::Read
                                                     : ParameterMode::Mut);
      return result;
    }
  auto alias = aliases.find(name);
  if (alias != aliases.end()) {
    auto &source = module.aliases[alias->second];
    auto &environment = aliasGenerics.at(&source);
    if (!environment.parameters.empty()) {
      auto arguments = genericArguments(source.genericParameters,
                                        syntax.arguments, environment, span);
      auto key = std::make_pair(alias->second, arguments);
      if (auto found = genericAliasInstances.find(key);
          found != genericAliasInstances.end()) {
        auto result = found->second;
        if (!syntax.view.empty())
          result = checked.types->viewType(result, syntax.view == "read"
                                                       ? ParameterMode::Read
                                                       : ParameterMode::Mut);
        return result;
      }
      if (!activeGenericAliases.insert(key).second) {
        error("type", span, "cyclic generic type alias");
        return Type::Unknown;
      }
      if (++genericDepth > limits::typeDepth) {
        --genericDepth;
        activeGenericAliases.erase(key);
        error("limit", span, "generic alias expansion limit exceeded");
        return Type::Unknown;
      }
      auto saved = genericEnvironment;
      genericEnvironment = &environment;
      auto pattern = annotation(source.target, source.span);
      genericEnvironment = saved;
      std::vector<TypeBinding> bindings;
      for (std::size_t i = 0; i < arguments.size(); ++i)
        bindings.push_back({environment.parameters[i], arguments[i]});
      auto result = checked.types->substitute(pattern, bindings);
      --genericDepth;
      activeGenericAliases.erase(key);
      genericAliasInstances.emplace(std::move(key), result);
      if (!syntax.view.empty())
        result = checked.types->viewType(result, syntax.view == "read"
                                                     ? ParameterMode::Read
                                                     : ParameterMode::Mut);
      return result;
    }
  }
  if (std::any_of(
          syntax.arguments.begin(), syntax.arguments.end(),
          [](const auto &argument) { return argument.region.empty(); })) {
    error("type", span, "type does not accept generic arguments");
    return Type::Unknown;
  }
  return std::nullopt;
}
// An argument whose type is still being inferred (for example `none`) agrees
// with a bound type wherever it is determined.
bool Checker::agreesWherePartial(Type bound, Type partial) {
  if (partial == Type::Unknown || bound == partial)
    return true;
  if ((checked.types->isView(bound) && checked.types->isView(partial)) ||
      (checked.types->isPointer(bound) && checked.types->isPointer(partial)))
    return agreesWherePartial(checked.types->view(bound).payload,
                              checked.types->view(partial).payload);
  if (!checked.types->isProduct(bound) || !checked.types->isProduct(partial))
    return false;
  const auto &left = checked.types->product(bound);
  const auto &right = checked.types->product(partial);
  if (left.kind != right.kind || left.genericOrigin != right.genericOrigin)
    return false;
  const auto &a = left.genericOrigin != Type::Unknown ? left.genericArguments
                                                      : left.components;
  const auto &b = right.genericOrigin != Type::Unknown ? right.genericArguments
                                                       : right.components;
  if (a.size() != b.size())
    return false;
  for (std::size_t i = 0; i < a.size(); ++i)
    if (!agreesWherePartial(a[i], b[i]))
      return false;
  return true;
}
bool Checker::inferGeneric(Type pattern, Type actual,
                           std::vector<TypeBinding> &bindings, Span span) {
  for (auto &binding : bindings)
    if (binding.parameter == pattern) {
      if (binding.argument == Type::Unknown) {
        binding.argument = actual;
        return true;
      }
      if (binding.argument == actual ||
          agreesWherePartial(binding.argument, actual))
        return true;
      error("type", span, "conflicting inferred generic arguments");
      return false;
    }
  if (pattern == actual) {
    // A generic body calling its own generic items binds each parameter to
    // itself.
    for (auto parameter : checked.types->typeParameters(pattern))
      for (auto &binding : bindings)
        if (binding.parameter == parameter && binding.argument == Type::Unknown)
          binding.argument = parameter;
    return true;
  }
  if (actual == Type::Never)
    return true;
  if ((checked.types->isView(pattern) && checked.types->isView(actual)) ||
      (checked.types->isPointer(pattern) && checked.types->isPointer(actual)))
    return inferGeneric(checked.types->view(pattern).payload,
                        checked.types->view(actual).payload, bindings, span);
  if (checked.types->isSlice(pattern)) {
    auto element = checked.types->slice(pattern).element;
    if (checked.types->isSlice(actual))
      return inferGeneric(element, checked.types->slice(actual).element,
                          bindings, span);
    if (checked.types->isProduct(actual)) {
      const auto &array = checked.types->product(actual);
      if (array.kind == AggregateKind::Array && array.components.size() == 1) {
        auto actualElement = array.components.front();
        return inferGeneric(element, actualElement, bindings, span);
      }
    }
    return false;
  }
  if (checked.types->isFunctionPointer(pattern) &&
      checked.types->isCallable(actual)) {
    const auto expected = checked.types->callable(pattern);
    const auto found = checked.types->callable(actual);
    if (expected.parameters.size() != found.parameters.size())
      return false;
    bool valid = true;
    for (std::size_t i = 0; i < found.parameters.size(); ++i)
      valid &= inferGeneric(expected.parameters[i].type,
                            found.parameters[i].type, bindings, span);
    valid &= inferGeneric(expected.result, found.result, bindings, span);
    if (expected.error != Type::Unknown && found.error != Type::Unknown)
      valid &= inferGeneric(expected.error, found.error, bindings, span);
    return valid;
  }
  if (!checked.types->isProduct(pattern) || !checked.types->isProduct(actual))
    return false;
  const auto left = checked.types->product(pattern);
  const auto right = checked.types->product(actual);
  if (left.kind != right.kind || left.kind == AggregateKind::NativeVector)
    return false;
  const auto &a = left.genericOrigin != Type::Unknown ? left.genericArguments
                                                      : left.components;
  const auto &b = right.genericOrigin != Type::Unknown ? right.genericArguments
                                                       : right.components;
  if (left.genericOrigin != right.genericOrigin || a.size() != b.size())
    return false;
  bool valid = true;
  for (std::size_t i = 0; i < a.size(); ++i)
    valid &= inferGeneric(a[i], b[i], bindings, span);
  if (left.kind == AggregateKind::Array && left.arrayCount != Type::Unknown)
    valid &= inferGeneric(
        left.arrayCount,
        right.arrayCount != Type::Unknown
            ? right.arrayCount
            : checked.types->constant(
                  checked.types->parameter(left.arrayCount).valueType,
                  right.fields.size()),
        bindings, span);
  return valid;
}
} // namespace mettle
