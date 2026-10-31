#include "syntax/parser/detail.h"
#include <string>
#include <string_view>
#include <utility>

namespace mettle::parsing {
namespace {
TypeSyntax namedType(std::string name) {
  TypeSyntax result;
  result.name = std::move(name);
  return result;
}

GenericArgument genericArgument(const GenericParameter &parameter) {
  GenericArgument result;
  result.span = parameter.span;
  if (parameter.kind == GenericParameterKind::Type) {
    result.type = std::make_shared<const TypeSyntax>(namedType(parameter.name));
  } else if (parameter.kind == GenericParameterKind::Region) {
    result.region = parameter.name;
  } else {
    auto value = std::make_shared<Node>();
    value->kind = Kind::Name;
    value->span = parameter.span;
    value->text = parameter.name;
    result.value = std::move(value);
  }
  return result;
}

TypeSyntax asyncFutureProjection(const Module::Interface &interface,
                                 const Function &method,
                                 std::string_view family) {
  TypeSyntax subject = namedType("Self");
  TypeSyntax bound = namedType(interface.name);
  for (const auto &parameter : interface.genericParameters)
    bound.arguments.push_back(genericArgument(parameter));

  TypeSyntax result;
  result.form = TypeForm::Projection;
  result.name = family;
  result.elements.push_back(std::move(subject));
  result.elements.push_back(std::move(bound));
  for (const auto &parameter : method.genericParameters)
    result.arguments.push_back(genericArgument(parameter));
  return result;
}
} // namespace

TypeSyntax Parser::boundType() {
  TypeSyntax bound;
  if (take("for")) {
    auto parameters = genericParameters();
    for (const auto &parameter : parameters) {
      if (parameter.kind != GenericParameterKind::Region)
        fail("higher-ranked binders may contain only regions");
      bound.binders.push_back(parameter.name);
    }
  }
  auto components = path();
  for (const auto &component : components) {
    if (!bound.name.empty())
      bound.name += "::";
    bound.name += component;
  }
  if (is("<"))
    bound.arguments = genericArguments();
  return bound;
}
Module::Associated Parser::associatedDeclaration() {
  Module::Associated result;
  result.span = peek().span;
  result.constant = take("const");
  if (!result.constant)
    expect("type");
  result.name = name().text;
  result.genericParameters = genericParameters();
  if (take(":")) {
    if (result.constant)
      result.annotation = type(false);
    else
      do {
        result.bounds.push_back(type(false));
      } while (take("+"));
  }
  result.constraints = genericConstraints();
  if (take("=")) {
    if (result.constant)
      result.constantValue = std::shared_ptr<const Node>(expr());
    else
      result.value = type();
  }
  result.span.end = tokens[position - 1].span.end;
  if (!is(";") && peek().kind != TokenKind::Newline && !is("}"))
    fail("expected an associated item separator");
  return result;
}
Module::Interface Parser::interfaceDeclaration() {
  Module::Interface result;
  result.span = expect("interface").span;
  result.name = name().text;
  result.genericParameters = genericParameters();
  if (take(":"))
    do {
      result.superinterfaces.push_back(type(false));
    } while (take("+"));
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto visible = visibility();
    if (is("type") || is("const")) {
      if (!metadata.empty())
        feature("attributes on associated items are not implemented");
      auto associated = associatedDeclaration();
      associated.visibility = std::move(visible);
      result.associated.push_back(std::move(associated));
    } else {
      std::string mode = "read";
      pendingAsync = take("async");
      if (is("mut") || is("take") || is("static"))
        mode = tokens[position++].text;
      auto method = function(true, true);
      if (method.constructor)
        fail("constructors cannot be declared in an interface", "signature");
      method.item.attributes = std::move(metadata);
      method.owner = result.name;
      method.interfaceOwner = result.name;
      method.receiver = mode;
      if (method.explicitReceiver) {
        if (mode != "read")
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.name = result.name + "." + method.name;
      method.item.visibility = std::move(visible);
      if (method.asynchronous) {
        method.asyncDefaultOutputInferred =
            method.body.get() && method.asyncOutput.empty();
        Module::Associated future;
        future.name =
            "$async_future_" + method.name.substr(method.name.rfind('.') + 1);
        future.span = method.span;
        future.visibility = method.item.visibility;
        future.asyncFuture = true;
        future.asyncFutureOutputInferred =
            method.asyncDefaultOutputInferred;
        future.genericParameters = method.genericParameters;
        future.constraints = method.constraints;

        TypeSyntax futureBound = namedType("core::future::Future");
        if (!method.asyncDefaultOutputInferred) {
          TypeSyntax output = method.asyncOutput;
          if (!method.asyncError.empty()) {
            TypeSyntax outcome;
            outcome.form = TypeForm::Outcome;
            outcome.elements.push_back(std::move(output));
            outcome.elements.push_back(method.asyncError);
            output = std::move(outcome);
          }
          GenericArgument binding;
          binding.binding = "Output";
          binding.span = method.span;
          binding.type = std::make_shared<const TypeSyntax>(std::move(output));
          futureBound.arguments.push_back(std::move(binding));
        }
        future.bounds.push_back(std::move(futureBound));
        if (method.body.get() && !method.asyncDefaultOutputInferred)
          future.value = method.annotation;

        method.asyncFuture = future.name;
        method.annotation =
            asyncFutureProjection(result, method, method.asyncFuture);
        method.error = {};
        result.associated.push_back(std::move(future));
      }
      if (mode != "static" && !method.explicitReceiver)
        method.parameters.insert(
            method.parameters.begin(),
            {"self", TypeSyntax{"Self", "", {}, {}}, method.span, mode});
      result.methods.push_back(std::move(method));
    }
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
Module::Implementation Parser::implementationDeclaration() {
  Module::Implementation result;
  result.unsafeImplementation = take("unsafe");
  result.span = peek().span;
  expect("extend");
  result.genericParameters = genericParameters();
  result.target = type(false);
  if (take("not")) {
    result.negative = true;
    result.interface = type(false);
    result.constraints = genericConstraints();
    result.span.end = tokens[position - 1].span.end;
    endItem("a negative extension");
    return result;
  }
  if (take("implements"))
    result.interface = type(false);
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto visible = visibility();
    if (is("type") || is("const")) {
      if (!metadata.empty())
        feature("attributes on associated items are not implemented");
      auto associated = associatedDeclaration();
      associated.visibility = std::move(visible);
      result.associated.push_back(std::move(associated));
    } else {
      std::string mode = "read";
      pendingAsync = take("async");
      if (is("mut") || is("take") || is("static"))
        mode = tokens[position++].text;
      auto method = function();
      method.item.attributes = std::move(metadata);
      method.owner = result.target.name;
      method.receiver = mode;
      if (method.constructor) {
        if (!result.interface.empty() || mode != "read")
          fail("constructors require an inherent extension without a receiver",
               "signature");
        method.annotation = result.target;
        method.receiver = "static";
      }
      if (method.explicitReceiver) {
        if (mode != "read" || method.constructor)
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.item.visibility = std::move(visible);
      if (!method.constructor && mode != "static" && !method.explicitReceiver)
        method.parameters.insert(method.parameters.begin(),
                                 {"self", result.target, method.span, mode});
      result.methods.push_back(std::move(method));
    }
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
} // namespace mettle::parsing
