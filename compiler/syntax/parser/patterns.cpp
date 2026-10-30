#include "syntax/parser/detail.h"

namespace mettle::parsing {
Pattern Parser::pattern(int minimum) {
  StateGuard guard(*this);
  if (++nesting > limits::parserNesting)
    fail("pattern nesting limit exceeded", "limit");
  Pattern result;
  result.span = peek().span;
  if (take("..")) {
    result.kind = PatternKind::Rest;
  } else if (is("(") || is("[")) {
    bool tuple = take("(");
    if (!tuple)
      expect("[");
    auto close = tuple ? ")" : "]";
    ++parens;
    result.kind = tuple ? PatternKind::Tuple : PatternKind::Array;
    while (!is(close)) {
      result.children.push_back(pattern());
      if (!take(","))
        break;
    }
    expect(close);
    --parens;
  } else if (take("_"))
    result.kind = PatternKind::Wildcard;
  else if (is("true") || is("false") || peek().kind == TokenKind::Integer ||
           peek().kind == TokenKind::Character ||
           peek().kind == TokenKind::Byte || is("-")) {
    result.kind = PatternKind::Literal;
    if (take("-")) {
      result.text = "-";
      if (peek().kind != TokenKind::Integer)
        fail("expected an integer literal after '-' in a pattern");
    }
    result.literalKind = peek().kind;
    result.text += tokens[position++].text;
  } else {
    bool builtin =
        is("none") || is("present") || is("success") || is("failure");
    result.text = builtin ? tokens[position++].text : name().text;
    while (take("::"))
      result.text += "::" + name().text;
    result.kind = builtin || result.text.find("::") != std::string::npos
                      ? PatternKind::Variant
                      : PatternKind::Binding;
    if (take("(")) {
      result.kind = PatternKind::Variant;
      ++parens;
      while (!is(")")) {
        result.children.push_back(pattern());
        if (!take(","))
          break;
      }
      expect(")");
      --parens;
    } else if (take("{")) {
      result.kind = PatternKind::Product;
      separators();
      while (!is("}")) {
        if (take("..")) {
          if (result.rest)
            fail("a product pattern has only one rest");
          result.rest = true;
          if (take(","))
            separators();
          if (!is("}"))
            fail("product rest must be the final field pattern");
          break;
        }
        auto field = name();
        Pattern child;
        if (take(":"))
          child = pattern();
        else
          child = {PatternKind::Binding, field.span, field.text};
        child.field = field.text;
        result.children.push_back(std::move(child));
        if (!take(",") && !is("}") && peek().kind != TokenKind::Newline)
          fail("expected a field pattern separator");
        separators();
      }
      expect("}");
    }
  }
  result.span.end = tokens[position - 1].span.end;
  if (result.kind == PatternKind::Literal && (is("..") || is("..="))) {
    bool inclusive = take("..=");
    if (!inclusive)
      expect("..");
    auto upper = pattern(1);
    if (upper.kind != PatternKind::Literal)
      fail("range pattern requires literal bounds");
    result.kind = PatternKind::Range;
    result.inclusive = inclusive;
    result.children.push_back(std::move(upper));
    result.span.end = result.children.back().span.end;
  }
  if (result.kind == PatternKind::Binding && take("@")) {
    if (take("..")) {
      result.kind = PatternKind::Rest;
      result.span.end = tokens[position - 1].span.end;
    } else {
      result.kind = PatternKind::At;
      result.children.push_back(pattern(1));
      result.span.end = result.children.back().span.end;
    }
  }
  if (minimum == 0 && take("|")) {
    Pattern alternatives{PatternKind::Or, result.span};
    alternatives.children.push_back(std::move(result));
    do {
      alternatives.children.push_back(pattern(1));
    } while (take("|"));
    alternatives.span.end = alternatives.children.back().span.end;
    result = std::move(alternatives);
  }
  --nesting;
  return result;
}

std::unique_ptr<Node> Parser::matchExpression() {
  StateGuard guard(*this);
  auto start = expect("match").span;
  auto result = node(Kind::Match, start, "read");
  if (is("mut") || is("take"))
    result->text = tokens[position++].text;
  result->children.push_back(expr());
  newlines();
  expect("{");
  parens = 0;
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto arm = node(Kind::Arm, peek().span);
    arm->patterns.push_back(pattern());
    if (take("if")) {
      arm->flag = true;
      arm->children.push_back(expr());
    }
    expect("=>");
    newlines();
    arm->children.push_back(expr());
    finish(*arm);
    result->children.push_back(std::move(arm));
    if (!take(",") && !is("}") && peek().kind != TokenKind::Newline)
      fail("expected a match arm separator");
    separators();
  }
  result->span.end = expect("}").span.end;
  finish(*result);
  return result;
}
} // namespace mettle::parsing
