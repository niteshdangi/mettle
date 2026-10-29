#include "syntax/lexer.h"
#include "syntax/parser/detail.h"
#include <algorithm>

namespace mettle::parsing {
Module::Product Parser::product() {
  Module::Product result;
  result.span = peek().span;
  result.copyRequested = take("copy");
  result.unionType = take("union");
  if (!result.unionType)
    expect("type");
  result.name = name().text;
  result.genericParameters = genericParameters(&result.regions);
  if (take("implements"))
    do {
      result.interfaces.push_back(boundType());
    } while (take("+"));
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto memberVisibility = visibility();
    if (!result.interfaces.empty() && (is("type") || is("const"))) {
      result.associated.push_back(associatedDeclaration());
      separators();
      continue;
    }
    if (is("fn") || is("unsafe") || is("mut") || is("take") || is("static") ||
        is("drop") || is("init")) {
      if (result.unionType)
        fail("union declarations contain fields only");
      Function method;
      std::string mode = "read";
      if (take("drop")) {
        if (result.hasDestructor)
          fail("a type may declare only one destructor");
        result.hasDestructor = true;
        method.name = "drop";
        method.annotation.name = "Unit";
        method.span = tokens[position - 1].span;
        newlines();
        method.body = block();
        method.destructor = true;
        mode = "mut";
      } else {
        if (take("mut"))
          mode = "mut";
        else if (take("take"))
          mode = "take";
        else if (take("static"))
          mode = "static";
        method = function();
      }
      method.owner = result.name;
      method.item.visibility = std::move(memberVisibility);
      method.item.attributes = std::move(metadata);
      method.receiver = mode;
      if (method.explicitReceiver) {
        if (mode != "read" || method.constructor)
          fail("explicit receiver cannot combine with a receiver modifier",
               "signature");
        method.receiver = method.parameters.front().mode.empty()
                              ? "read"
                              : method.parameters.front().mode;
      }
      method.name = result.name + "." + method.name;
      if (method.constructor) {
        if (mode != "read")
          fail("custom constructors cannot select a receiver modifier");
        method.annotation.name = result.name;
        method.annotation.regions = result.regions;
        method.receiver = "static";
        for (const auto &existing : result.methods)
          if (existing.constructor)
            fail("a type may declare only one custom constructor");
      } else if (mode != "static" && !method.explicitReceiver)
        method.parameters.insert(
            method.parameters.begin(),
            {"self", TypeSyntax{result.name, "", {}, result.regions},
             method.span, mode});
      for (const auto &parameter : result.genericParameters)
        if (parameter.kind != GenericParameterKind::Region) {
          GenericArgument argument;
          auto syntax = std::make_shared<TypeSyntax>();
          syntax->name = parameter.name;
          argument.type = std::move(syntax);
          if (method.constructor)
            method.annotation.arguments.push_back(argument);
          else if (mode != "static" && !method.explicitReceiver)
            method.parameters.front().annotation.arguments.push_back(argument);
        }
      result.methods.push_back(std::move(method));
      separators();
      continue;
    }
    auto field = name();
    expect(":");
    result.fields.push_back({field.text, type(), field.span});
    result.fields.back().visibility = std::move(memberVisibility);
    result.fields.back().attributes = std::move(metadata);
    if (result.unionType && take(",")) {
      separators();
      continue;
    }
    if (peek().kind != TokenKind::Newline && !is(";") && !is("}"))
      fail("expected a newline or ';' between fields");
    separators();
  }
  result.span.end = expect("}").span.end;
  bool structuralPin = std::any_of(
      result.fields.begin(), result.fields.end(), [](const auto &field) {
        return std::any_of(
            field.attributes.begin(), field.attributes.end(),
            [](const auto &attribute) { return attribute.name == "pinned"; });
      });
  if (structuralPin)
    for (auto &method : result.methods)
      if (method.destructor) {
        TypeSyntax reference;
        reference.view = "mut";
        reference.nested = std::make_shared<const TypeSyntax>(
            std::move(method.parameters.front().annotation));
        TypeSyntax pinned;
        pinned.form = TypeForm::Pinned;
        pinned.elements.push_back(std::move(reference));
        method.parameters.front().annotation = std::move(pinned);
      }
  return result;
}
Function Parser::function(bool allowDeclaration) {
  Function result;
  result.unsafeFunction = take("unsafe");
  result.constructor = is("init");
  if (result.constructor) {
    result.span = expect("init").span;
    result.name = "init";
  } else {
    result.span = expect("fn").span;
    result.name = name().text;
  }
  result.genericParameters = genericParameters(&result.regions);
  expect("(");
  ++parens;
  if (!is(")")) {
    do {
      if (is(")"))
        break;
      if (take("...")) {
        if (result.parameters.empty())
          fail("a variadic function requires a named fixed parameter");
        result.variadic = true;
        break;
      }
      bool receiver = is("receiver") && peek(1).text == "self";
      if (receiver)
        ++position;
      auto parameter = pattern();
      if (receiver) {
        if (!result.parameters.empty() ||
            parameter.kind != PatternKind::Binding || parameter.text != "self")
          fail("explicit receiver must be first and bind self", "signature");
        result.explicitReceiver = true;
      }
      bool named = parameter.kind == PatternKind::Binding;
      auto parameterName =
          named
              ? parameter.text
              : "<parameter." + std::to_string(result.parameters.size()) + ">";
      expect(":");
      if (take("...")) {
        if (result.parameters.empty() || !named)
          fail("a variadic cursor requires a named fixed parameter");
        result.variadic = true;
        result.variadicCursor = std::move(parameterName);
        result.variadicSpan = parameter.span;
        break;
      }
      std::string mode;
      if (is("take") || is("read") || is("mut"))
        mode = tokens[position++].text;
      result.parameters.push_back(
          {std::move(parameterName), type(), parameter.span, mode});
      if (!named)
        result.parameters.back().pattern = std::move(parameter);
      if (take("="))
        result.parameters.back().defaultValue = expr();
    } while (take(","));
  }
  expect(")");
  --parens;
  if (!result.constructor && take(":"))
    result.annotation = type(false);
  if (is("->")) {
    ++position;
    fail("function results use ': Type', not '->'");
  }
  if (take("throws"))
    result.error = type();
  result.constraints = genericConstraints();
  if (allowDeclaration &&
      (is(";") || peek().kind == TokenKind::Newline || is("}"))) {
    auto saved = position;
    newlines();
    if (!is("{")) {
      position = saved;
      if (result.annotation.empty())
        fail("interface method declarations require an explicit result type",
             "signature");
      result.span.end = tokens[position - 1].span.end;
      take(";");
      return result;
    }
  }
  newlines();
  result.body = block();
  result.span.end = result.body->span.end;
  return result;
}
std::unique_ptr<Node> Parser::block() {
  if (++nesting > limits::parserNesting)
    fail("block nesting limit exceeded", "limit");
  auto start = expect("{").span;
  auto savedParens = parens;
  parens = 0;
  auto result = node(Kind::Block, start);
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto before = position;
    try {
      auto statement = stmt();
      bool separated = false;
      while (peek().kind == TokenKind::Newline || is(";")) {
        statement->semicolon |= is(";");
        separated = true;
        ++position;
      }
      if (!separated && !is("}"))
        fail("expected a newline or ';' between statements");
      result->children.push_back(std::move(statement));
    } catch (ParseFailure &) {
      if (position == before && peek().kind != TokenKind::End && !is("}"))
        ++position;
      while (peek().kind != TokenKind::End && !is("}") &&
             peek().kind != TokenKind::Newline && !is(";"))
        ++position;
      separators();
    }
  }
  result->span.end = expect("}").span.end;
  parens = savedParens;
  --nesting;
  finish(*result);
  return result;
}
} // namespace mettle::parsing
