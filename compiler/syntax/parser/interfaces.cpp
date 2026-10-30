#include "syntax/parser/detail.h"

namespace mettle::parsing {
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
      auto method = function(true);
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
  if (!take("impl"))
    expect("extend");
  result.genericParameters = genericParameters();
  result.target = type(false);
  if (take("not")) {
    result.negative = true;
    result.interface = type(false);
    result.constraints = genericConstraints();
    result.span.end = expect(";").span.end;
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
      if (method.explicitReceiver) {
        if (mode != "read")
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.item.visibility = std::move(visible);
      if (mode != "static" && !method.explicitReceiver)
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
