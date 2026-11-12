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
    auto key = nameKey(parameter.name, parameter.context);
    if (result.names.contains(key)) {
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
      if (!constraint.region &&
          nameKey(constraint.subject.name, constraint.subject.context) == key)
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
    result.names.emplace(key, type);
    genericNames.emplace(type, key);
    result.parameters.push_back(type);
    result.bounds[type] = parameter.bounds;
  }
  for (const auto &constraint : constraints) {
    if (constraint.region)
      continue;
    auto found = result.names.find(
        nameKey(constraint.subject.name, constraint.subject.context));
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
    if (imported(product.span))
      continue;
    auto environment =
        makeGenericEnvironment(product.genericParameters, product.constraints);
    environment.declarationSpan = product.span;
    auto type = typeNames.at(definitionName(product.span, product.name));
    checked.types->setGenericParameters(type, environment.parameters);
    productGenerics.emplace(&product, std::move(environment));
  }
  for (const auto &alias : module.aliases) {
    if (imported(alias.span))
      continue;
    auto environment =
        makeGenericEnvironment(alias.genericParameters, alias.constraints);
    environment.declarationSpan = alias.span;
    aliasGenerics.emplace(&alias, std::move(environment));
  }
  for (std::size_t i = 0; i < module.interfaces.size(); ++i) {
    const auto &interface = module.interfaces[i];
    if (imported(interface.span))
      continue;
    GenericEnvironment parent;
    parent.names[nameKey("Self", interface.span)] =
        checked.interfaceData->definitions[i].self;
    auto environment = makeGenericEnvironment(interface.genericParameters,
                                              interface.constraints, &parent);
    environment.declarationSpan = interface.span;
    checked.interfaceData->definitions[i].parameters = environment.parameters;
    interfaceGenerics.emplace(&interface, std::move(environment));
  }
  for (const auto &product : module.products)
    if (!imported(product.span))
      validateGenericEnvironment(product.genericParameters, product.constraints,
                                 productGenerics.at(&product));
  for (const auto &alias : module.aliases)
    if (!imported(alias.span))
      validateGenericEnvironment(alias.genericParameters, alias.constraints,
                                 aliasGenerics.at(&alias));
  for (const auto &interface : module.interfaces)
    if (!imported(interface.span) &&
        std::none_of(interface.genericParameters.begin(),
                     interface.genericParameters.end(),
                     [](const auto &parameter) {
                       return parameter.kind == GenericParameterKind::Region;
                     }))
      validateGenericEnvironment(interface.genericParameters,
                                 interface.constraints,
                                 interfaceGenerics.at(&interface));
  for (auto &function : module.functions) {
    if (imported(function.span))
      continue;
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
    if (imported(function.span))
      continue;
    if (function.implementation >= 0) {
      auto saved = genericEnvironment;
      genericEnvironment = &functionGenerics.at(&function);
      const auto &implementation =
          module.implementations[function.implementation];
      genericEnvironment->names[nameKey("Self", function.lexicalContext)] =
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
    auto found = environment.names.find(
        nameKey(constraint.subject.name, constraint.subject.context));
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
    auto found = environment.names.find(
        nameKey(constraint.subject.name, constraint.subject.context));
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
        [&](Type type) {
          auto key = genericNames.find(type);
          return key != genericNames.end() &&
                 key->second == nameKey(parameter.name, parameter.context);
        });
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
    auto self =
        environment.names.find(nameKey("Self", environment.declarationSpan));
    bool dependsOnSelf = self != environment.names.end() &&
                         std::find(dependencies.begin(), dependencies.end(),
                                   self->second) != dependencies.end();
    if (!dependsOnSelf)
      deferredObligations.push_back({&environment,
                                     environment,
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
  for (auto &item : pending) {
    genericEnvironment = item.context ? &*item.context : nullptr;
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
  auto open = [&](Type type) {
    for (auto parameter : checked.types->typeParameters(type))
      for (const auto &binding : bindings)
        if (binding.parameter == parameter && binding.argument == Type::Unknown)
          return true;
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
          if (argument.binding.empty() || !argument.type)
            continue;
          auto slot = bindings.end();
          Type pattern = Type::Unknown;
          if (argument.type->form == TypeForm::Named) {
            auto target = environment.names.find(
                nameKey(argument.type->name, argument.type->context));
            if (target == environment.names.end())
              continue;
            slot = std::find_if(
                bindings.begin(), bindings.end(), [&](const auto &binding) {
                  return binding.parameter == target->second &&
                         binding.argument == Type::Unknown;
                });
            if (slot == bindings.end())
              continue;
          } else if (argument.type->form == TypeForm::Tuple) {
            auto savedPattern = genericEnvironment;
            genericEnvironment = const_cast<GenericEnvironment *>(&environment);
            pattern = annotation(*argument.type, environment.declarationSpan, {});
            genericEnvironment = savedPattern;
            if (pattern == Type::Unknown || !open(pattern))
              continue;
          } else
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
          if (value == Type::Unknown)
            continue;
          if (slot == bindings.end()) {
            auto attempt = bindings;
            if (!inferGeneric(pattern, value, attempt, span))
              continue;
            for (std::size_t index = 0; index < bindings.size(); ++index)
              if (bindings[index].argument == Type::Unknown &&
                  attempt[index].argument != Type::Unknown) {
                bindings[index].argument = attempt[index].argument;
                progress = true;
              }
            continue;
          }
          if (std::any_of(bindings.begin(), bindings.end(),
                          [&](const auto &binding) {
                            return binding.parameter == value;
                          }))
            continue;
          slot->argument = value;
          progress = true;
        }
    }
    return progress;
  };
  // `where Self.Item = read T from r` determines `T` once `Self` is known:
  // normalize the closed side and match the open side against it.
  auto structural = [&](Type pattern, Type closed) {
    if (!open(pattern) || open(closed) || checked.types->isParameter(pattern))
      return false;
    interfaces::Solver solver(*checked.types, *checked.interfaceData,
                              diagnostics, interfaceAssumptions(),
                              regionEnvironment());
    auto actual = solver.normalize(closed, bindings, span);
    if (actual == Type::Unknown || open(actual))
      return false;
    auto attempt = bindings;
    if (!inferGeneric(pattern, actual, attempt, span))
      return false;
    bool progress = false;
    for (std::size_t index = 0; index < bindings.size(); ++index)
      if (bindings[index].argument == Type::Unknown &&
          attempt[index].argument != Type::Unknown) {
        bindings[index].argument = attempt[index].argument;
        progress = true;
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
      changed |= structural(equality.argument, left);
      changed |= structural(equality.parameter, right);
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
  if (environment.equalities.empty())
    return;
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
    // Region parameters are solved by the region pass, not by type equality.
    if (left != Type::Unknown && right != Type::Unknown &&
        checked.types->eraseRegions(left) != checked.types->eraseRegions(right))
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
    if (genericEnvironment) {
      auto found =
          genericEnvironment->names.find(nameKey(node.text, node.context));
      if (found != genericEnvironment->names.end() &&
          checked.types->isConstant(found->second))
        return checked.types->parameter(found->second).valueType;
    }
    if (auto storage = staticName(node.text, node.span, node.context))
      return checked.staticStorage[*storage].type;
    if (auto primitive = machineValue(node))
      if (facts(node).numeric && isInteger(inference.value(*primitive)))
        return inference.value(*primitive);
    if (node.text.find("::") != std::string::npos)
      if (auto associated = associatedConstant(node))
        return checked.types->parameter(*associated).valueType;
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
  if (node.kind == Kind::Name && genericEnvironment) {
    auto found =
        genericEnvironment->names.find(nameKey(node.text, node.context));
    if (found != genericEnvironment->names.end() &&
        checked.types->isConstant(found->second))
      return found->second;
  }
  if (node.kind == Kind::Name)
    if (auto primitive = machineValue(node))
      if (facts(node).numeric && isInteger(inference.value(*primitive))) {
        facts(node).type = inference.value(*primitive);
        return checked.types->constant(facts(node).type, *facts(node).numeric);
      }
  if (node.kind == Kind::Name)
    if (auto storage = staticName(node.text, node.span, node.context)) {
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
    if (facts(node).constantValue) {
      error("constant", node.span,
            "required integer expression needs a scalar associated constant");
      return Type::Unknown;
    }
    if (reportedErrors != errorsBefore)
      return Type::Unknown;
  }
  if (node.kind == Kind::Name && node.text.find("::") == std::string::npos) {
    auto errorsBefore = reportedErrors;
    if (auto associated = associatedConstant(node))
      return *associated;
    if (facts(node).constantValue) {
      error("constant", node.span,
            "required integer expression needs a scalar associated constant");
      return Type::Unknown;
    }
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
                displayType(*checked.types, type) + " range");
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
                displayType(*checked.types, binding.parameter) + "'");
    result.push_back(binding.argument);
  }
  std::vector<Type> deferred;
  if (!implementationsRegistered)
    for (const auto &binding : bindings)
      if (binding.argument != Type::Unknown &&
          !checked.types->isParameter(binding.argument))
        deferred.push_back(binding.parameter);
  if (!deferred.empty()) {
    obligationParameters = &deferred;
    genericObligations(environment, bindings, span);
    obligationParameters = nullptr;
    deferredObligations.push_back({&environment,
                                   genericEnvironment
                                       ? std::make_optional(*genericEnvironment)
                                       : std::nullopt,
                                   bindings, deferred, span});
  } else
    genericObligations(environment, bindings, span);
  return result;
}
bool Checker::genericObligations(const GenericEnvironment &environment,
                                 std::span<const TypeBinding> bindings,
                                 Span span,
                                 std::span<const RegionBinding> regions,
                                 const Node *call) {
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
        if (*property == interfaces::Property::Static && call) {
          std::vector<RegionId> regions;
          interfaces::Solver proof(*checked.types, *checked.interfaceData,
                                   diagnostics, interfaceAssumptions(),
                                   regionEnvironment());
          proof.collectStaticRegions(&regions);
          if (proof.prove({binding.argument, Type::Unknown, *property}, span,
                          false)) {
            if (!regions.empty())
              facts(*call).deferredInterfaceBounds.push_back(
                  {binding.parameter, Type::Unknown, bound, *property});
            continue;
          }
        }
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
        const auto declared = interfaceBound(bound, environment.declarationSpan,
                                             {}, binding.parameter);
        auto required = checked.types->substitute(declared, bindings);
        required = checked.types->substituteRegions(required, regions);
        genericEnvironment = caller;
        required = normalizeGenericType(required, {}, span);
        interfaces::Solver proof(*checked.types, *checked.interfaceData,
                                 diagnostics, interfaceAssumptions(),
                                 regionEnvironment());
        std::vector<RegionId> staticRegions;
        if (call)
          proof.collectStaticRegions(&staticRegions);
        if (proof.prove({binding.argument, required}, span, false)) {
          if (call && (checked.types->containsViews(binding.argument) ||
                       !staticRegions.empty()))
            facts(*call).deferredInterfaceBounds.push_back(
                {binding.parameter, declared, bound});
          continue;
        }
        if (call && checked.types->containsViews(binding.argument)) {
          interfaces::Solver shape(*checked.types, *checked.interfaceData,
                                   diagnostics, interfaceAssumptions(), {},
                                   true);
          if (shape.prove({binding.argument, required}, span, false)) {
            facts(*call).deferredInterfaceBounds.push_back(
                {binding.parameter, declared, bound});
            continue;
          }
        }
        valid &= interfaceObligation(binding.argument, required, span);
      }
  }
  genericEnvironment = caller;
  for (const auto &[subject, bounds] : environment.bounds) {
    if (checked.types->isParameter(subject))
      continue;
    for (const auto &bound : bounds) {
      if (bound.name == "unsized" || bound.name == "?Sized")
        continue;
      genericEnvironment = const_cast<GenericEnvironment *>(&environment);
      auto property = propertyBound(bound, environment.declarationSpan)
                          .value_or(interfaces::Property::Interface);
      if (property == interfaces::Property::Unpin) {
        genericEnvironment = caller;
        continue;
      }
      auto declared =
          bound.form == TypeForm::Callable
              ? callableAnnotation(bound, environment.declarationSpan, {})
          : property == interfaces::Property::Interface
              ? interfaceBound(bound, environment.declarationSpan, {}, subject)
              : Type::Unknown;
      genericEnvironment = caller;
      if (obligationParameters) {
        auto dependencies = checked.types->typeParameters(subject);
        auto interfaceDependencies = checked.types->typeParameters(declared);
        dependencies.insert(dependencies.end(), interfaceDependencies.begin(),
                            interfaceDependencies.end());
        bool selected = std::any_of(
            dependencies.begin(), dependencies.end(), [&](Type parameter) {
              return std::find(obligationParameters->begin(),
                               obligationParameters->end(),
                               parameter) != obligationParameters->end();
            });
        if (selected != obligationsOnly)
          continue;
      }
      auto actual = normalizeGenericType(subject, bindings, span);
      actual = checked.types->substituteRegions(actual, regions);
      auto required = normalizeGenericType(declared, bindings, span);
      required = checked.types->substituteRegions(required, regions);
      if (bound.form == TypeForm::Callable) {
        valid &= callableObligation(actual, required, span);
        continue;
      }
      interfaces::Solver proof(*checked.types, *checked.interfaceData,
                               diagnostics, interfaceAssumptions(),
                               regionEnvironment());
      if (caller)
        proof.setEqualities(caller->equalities);
      std::vector<RegionId> staticRegions;
      if (call)
        proof.collectStaticRegions(&staticRegions);
      bool regional = checked.types->containsViews(declared) ||
                      checked.types->containsViews(actual) ||
                      checked.types->containsViews(required);
      bool holds = proof.prove({actual, required, property}, span, false);
      if (!holds && call && regional) {
        interfaces::Solver shape(*checked.types, *checked.interfaceData,
                                 diagnostics, interfaceAssumptions(), {}, true);
        if (caller)
          shape.setEqualities(caller->equalities);
        holds = shape.prove({actual, required, property}, span, false);
      }
      if (holds) {
        if (call && (regional || !staticRegions.empty()))
          facts(*call).deferredInterfaceBounds.push_back(
              {subject, declared, bound, property});
        continue;
      }
      if (property == interfaces::Property::Interface)
        valid &= interfaceObligation(actual, required, span);
      else {
        error("type", span,
              "unsatisfied interface bound '" + displayPath(bound.name) + "'");
        valid = false;
      }
    }
  }
  auto saved = genericEnvironment;
  genericEnvironment = const_cast<GenericEnvironment *>(&environment);
  auto requirements = interfaceAssumptions();
  genericEnvironment = saved;
  if (std::none_of(requirements.begin(), requirements.end(),
                   [](const auto &requirement) {
                     return requirement.property == interfaces::Property::Unpin;
                   }))
    return valid;
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
    auto found =
        genericEnvironment->names.find(nameKey(syntax.name, syntax.context));
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
  auto name = typeName(syntax.name, span, owner, syntax.context);
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
          source.context = parameter.context;
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
  if (typeNames.contains(name) &&
      std::any_of(
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
  if (left.kind == AggregateKind::Array && left.arrayCount != Type::Unknown) {
    auto count = right.arrayCount;
    if (auto length = checked.types->arrayLength(actual)) {
      auto valueType = checked.types->parameter(left.arrayCount).valueType;
      NumericLiteral value;
      value.magnitude[0] = *length;
      if (!integerLiteralFits(value, valueType, pointerBits())) {
        error(
            "type", span,
            "inferred array length is outside the const parameter type range");
        return false;
      }
      count = checked.types->constant(valueType, value);
    }
    valid &= inferGeneric(left.arrayCount, count, bindings, span);
  }
  return valid;
}
} // namespace mettle
