#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::unique_ptr<Node> Parser::expr(int minimum) {
  if (++nesting > limits::parserNesting)
    fail("expression nesting limit exceeded", "limit");
  auto left = primary();
  bool compared = false;
  while (int level = binaryPrecedence(peek().text)) {
    if (level < minimum)
      break;
    if (level == 3 && compared)
      fail("comparisons do not chain");
    compared |= level == 3;
    auto operation = tokens[position++];
    newlines();
    auto result = node(Kind::Binary, left->span, operation.text);
    result->children.push_back(std::move(left));
    result->children.push_back(expr(level + 1));
    finish(*result);
    left = std::move(result);
  }
  --nesting;
  return left;
}
std::unique_ptr<Node> Parser::primary() {
  if (++nesting > limits::parserNesting)
    fail("expression nesting limit exceeded", "limit");
  auto token = peek();
  std::unique_ptr<Node> result;
  if (is("["))
    feature("array expressions require later aggregate support");
  if (take("-") || take("!") || take("take") || take("read") || take("mut") ||
      take("*")) {
    result = node(Kind::Unary, token.span, token.text);
    newlines();
    result->children.push_back(primary());
  } else if (take("if")) {
    result = node(Kind::If, token.span);
    result->children.push_back(expr());
    newlines();
    result->children.push_back(block());
    auto saved = position;
    newlines();
    if (take("else")) {
      newlines();
      result->children.push_back(is("if") ? primary() : block());
    } else
      position = saved;
  } else if (is("{")) {
    result = block();
  } else if (take("(")) {
    ++parens;
    if (take(")"))
      result =
          node(Kind::Unit, {token.span.begin, tokens[position - 1].span.end});
    else {
      result = node(Kind::Group, token.span);
      result->children.push_back(expr());
      if (is(","))
        feature("tuples require later aggregate support");
      result->span.end = expect(")").span.end;
    }
    --parens;
  } else if (token.kind == TokenKind::Integer) {
    ++position;
    result = node(Kind::Integer, token.span, token.text);
  } else if (take("true") || take("false")) {
    result = node(Kind::Boolean, token.span, token.text);
  } else {
    if (token.kind == TokenKind::Word) {
      if (isUnsupportedExpressionWord(token.text))
        feature("this language feature is not implemented yet");
    }
    auto identifier = name();
    result = node(Kind::Name, identifier.span, identifier.text);
  }
  for (;;) {
    if (take(".")) {
      newlines();
      auto member = is("drop") ? tokens[position++] : name();
      auto field = node(Kind::Field, result->span, member.text);
      field->span.end = member.span.end;
      field->children.push_back(std::move(result));
      finish(*field);
      result = std::move(field);
      continue;
    }
    if (!take("("))
      break;
    auto call = node(Kind::Call, result->span);
    call->children.push_back(std::move(result));
    ++parens;
    if (!is(")")) {
      do {
        if (is(")"))
          break;
        std::string label;
        if (peek().kind == TokenKind::Word && peek(1).text == ":") {
          label = name().text;
          expect(":");
        }
        auto argument = expr();
        argument->name = label;
        call->children.push_back(std::move(argument));
      } while (take(","));
    }
    call->span.end = expect(")").span.end;
    --parens;
    finish(*call);
    result = std::move(call);
  }
  if (is("[") || is("::") || is("?."))
    feature("extended postfix expressions are not implemented in I02");
  finish(*result);
  --nesting;
  return result;
}
} // namespace mettle::parsing
