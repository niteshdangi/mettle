#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
Module::Product Parser::product() {
  Module::Product result;
  result.span = peek().span;
  result.copyRequested = take("copy");
  expect("type");
  result.name = name().text;
  if (take("<")) {
    do {
      if (!take("region"))
        feature("generic type parameters require I05");
      result.regions.push_back(name().text);
    } while (take(","));
    expect(">");
  }
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    if (is("fn") || is("mut") || is("take") || is("drop")) {
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
        method = function();
      }
      method.owner = result.name;
      method.receiver = mode;
      method.name = result.name + "." + method.name;
      method.parameters.insert(method.parameters.begin(),
                               {"self",
                                TypeSyntax{result.name, "", {}, result.regions},
                                method.span, mode});
      result.methods.push_back(std::move(method));
      separators();
      continue;
    }
    if (is("init") || is("static"))
      feature("custom constructors and static members require I04");
    auto field = name();
    expect(":");
    result.fields.push_back({field.text, type(), field.span});
    if (peek().kind != TokenKind::Newline && !is(";") && !is("}"))
      fail("expected a newline or ';' between fields");
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
Function Parser::function() {
  Function result;
  result.span = expect("fn").span;
  auto identifier = name();
  result.name = identifier.text;
  if (take("<")) {
    do {
      if (!take("region"))
        feature("generic functions require I05");
      result.regions.push_back(name().text);
    } while (take(","));
    expect(">");
  }
  expect("(");
  ++parens;
  if (!is(")")) {
    do {
      if (is(")"))
        break;
      auto parameter = name();
      expect(":");
      std::string mode;
      if (is("take") || is("read") || is("mut"))
        mode = tokens[position++].text;
      result.parameters.push_back(
          {parameter.text, type(), parameter.span, mode});
      if (is("="))
        feature("parameter defaults require I04");
    } while (take(","));
  }
  expect(")");
  --parens;
  if (take(":"))
    result.annotation = type();
  if (is("->")) {
    ++position;
    fail("function results use ': Type', not '->'");
  }
  if (is("throws"))
    feature("typed errors require I04");
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
