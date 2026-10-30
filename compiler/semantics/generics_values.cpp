#include "semantics/checker.h"
#include <algorithm>

namespace mettle {
void Checker::seedInterfaceBindings(const Node &node,
                                    const GenericEnvironment &environment,
                                    std::vector<TypeBinding> &bindings) {
  const auto &dispatch = facts(node);
  auto seed = [&](std::string_view name, Type argument) {
    auto parameter = environment.names.find(std::string(name));
    if (parameter == environment.names.end())
      return;
    for (auto &binding : bindings)
      if (binding.parameter == parameter->second)
        binding.argument = argument;
  };
  if (dispatch.interfaceSelf != Type::Unknown)
    seed("Self", dispatch.interfaceSelf);
  if (!checked.types->isErased(dispatch.interfaceType))
    return;
  const auto &descriptor = checked.types->erased(dispatch.interfaceType);
  const auto &syntax = module.interfaces.at(descriptor.declaration);
  std::size_t argument = 0;
  for (const auto &parameter : syntax.genericParameters) {
    if (parameter.kind == GenericParameterKind::Region)
      continue;
    if (argument < descriptor.arguments.size())
      seed(parameter.name, descriptor.arguments[argument++]);
  }
}
void Checker::explicitGenericBindings(const Function &function,
                                      const Node &callee,
                                      const GenericEnvironment &environment,
                                      std::vector<TypeBinding> &bindings,
                                      Span span) {
  std::vector<const GenericParameter *> owner, selected;
  if (function.implementation < 0 && !function.owner.empty())
    for (const auto *product :
         productsNamed(typeName(function.owner, function.span)))
      for (const auto &parameter : product->genericParameters)
        if (parameter.kind != GenericParameterKind::Region)
          owner.push_back(&parameter);
  for (std::size_t i = function.implicitGenericParameters;
       i < function.genericParameters.size(); ++i)
    if (function.genericParameters[i].kind != GenericParameterKind::Region)
      selected.push_back(&function.genericParameters[i]);
  if (function.implementation >= 0 && !function.owner.empty()) {
    // Owner arguments of an inherent impl bind the impl parameters that the
    // target type names, in order.
    const auto &target =
        module
            .implementations[static_cast<std::size_t>(function.implementation)]
            .target;
    for (const auto &argument : target.arguments) {
      if (!argument.region.empty())
        continue;
      const GenericParameter *bound = nullptr;
      if (argument.type && argument.type->form == TypeForm::Named &&
          argument.type->arguments.empty())
        for (std::size_t i = 0; i < function.implicitGenericParameters &&
                                i < function.genericParameters.size();
             ++i)
          if (function.genericParameters[i].name == argument.type->name &&
              function.genericParameters[i].kind !=
                  GenericParameterKind::Region)
            bound = &function.genericParameters[i];
      owner.push_back(bound);
    }
  }
  if (function.constructor)
    selected.insert(selected.begin(), owner.begin(), owner.end());
  auto bind = [&](const std::vector<GenericArgument> &arguments,
                  const std::vector<const GenericParameter *> &parameters) {
    std::size_t index = 0;
    for (const auto &argument : arguments) {
      if (!argument.region.empty())
        continue;
      if (index >= parameters.size()) {
        error("type", span, "excess explicit generic arguments");
        break;
      }
      const auto *declared = parameters[index++];
      if (!declared)
        continue;
      const auto &parameter = *declared;
      auto identity = environment.names.at(parameter.name);
      auto binding = std::find_if(bindings.begin(), bindings.end(),
                                  [&](const TypeBinding &candidate) {
                                    return candidate.parameter == identity;
                                  });
      if (binding == bindings.end())
        binding = std::find_if(
            bindings.begin(), bindings.end(),
            [&](const TypeBinding &candidate) {
              return checked.types->name(candidate.parameter) == parameter.name;
            });
      if (binding == bindings.end()) {
        error("type", span, "generic argument has no declaration binding");
        continue;
      }
      if (!inferredArgument(argument))
        binding->argument = genericArgument(argument, binding->parameter);
    }
  };
  bind(callee.ownerGenericArguments, owner);
  bind(callee.genericArguments, selected);
}
bool Checker::inferredArgument(const GenericArgument &argument) {
  return argument.type && argument.type->form == TypeForm::Named &&
         argument.type->name == "_" && argument.type->arguments.empty();
}
Type Checker::genericArgument(const GenericArgument &argument, Type parameter) {
  if (checked.types->isParameter(parameter)) {
    if (argument.type)
      return annotation(*argument.type, argument.span);
    error("type", argument.span, "expected a type argument");
    return Type::Unknown;
  }
  Type value = Type::Unknown;
  if (argument.value)
    value = constantType(*argument.value,
                         checked.types->parameter(parameter).valueType);
  else if (argument.type && argument.type->form == TypeForm::Named &&
           argument.type->arguments.empty()) {
    Node name{};
    name.kind = Kind::Name;
    name.text = argument.type->name;
    name.span = argument.span;
    value = constantType(name);
  } else
    error("type", argument.span, "expected a constant argument");
  return value;
}
std::optional<CallableType> Checker::genericFunctionValue(Node &node,
                                                          std::size_t callee) {
  auto &function = module.functions[callee];
  auto &environment = functionGenerics.at(&function);
  if (environment.parameters.empty())
    return std::nullopt;
  auto caller = genericEnvironment;
  genericEnvironment = &environment;
  auto signature = functionSignature(callee);
  genericEnvironment = caller;
  std::vector<TypeBinding> bindings;
  for (auto parameter : environment.parameters)
    bindings.push_back({parameter, Type::Unknown});
  seedInterfaceBindings(node, environment, bindings);
  explicitGenericBindings(function, node, environment, bindings, node.span);
  if (auto context = closureContexts.find(&node);
      context != closureContexts.end() &&
      checked.types->isFunctionPointer(context->second)) {
    const auto expected = checked.types->callable(context->second);
    if (expected.parameters.size() != signature.parameters.size())
      error("type", node.span, "generic function value has incompatible arity");
    else {
      for (std::size_t i = 0; i < signature.parameters.size(); ++i)
        inferGeneric(signature.parameters[i].type, expected.parameters[i].type,
                     bindings, node.span);
      inferGeneric(signature.result, expected.result, bindings, node.span);
    }
  }
  completeGenericBindings(environment, bindings, node.span);
  for (const auto &binding : bindings) {
    if (binding.argument == Type::Unknown)
      error("type", node.span,
            "cannot infer generic function-value arguments; use <...>");
    facts(node).typeArguments.push_back(binding.argument);
  }
  genericObligations(environment, bindings, node.span);
  for (auto &parameter : signature.parameters)
    parameter.type = normalizeGenericType(parameter.type, bindings, node.span);
  signature.result =
      normalizeGenericType(signature.result, bindings, node.span);
  signature.error = normalizeGenericType(signature.error, bindings, node.span);
  signature.abiResult =
      normalizeGenericType(signature.abiResult, bindings, node.span);
  return signature;
}
} // namespace mettle
