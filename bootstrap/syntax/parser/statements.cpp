#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
void Parser::conditions(Node &owner) {
  auto clause = [&] {
    auto result = node(Kind::Condition, peek().span);
    if (take("let")) {
      result->patterns.push_back(pattern());
      expect("=");
    }
    result->children.push_back(expr());
    finish(*result);
    return result;
  };
  auto first = clause();
  if (!take(",")) {
    owner.patterns = std::move(first->patterns);
    owner.children.push_back(std::move(first->children[0]));
    return;
  }
  auto chain = node(Kind::ConditionChain, first->span);
  chain->children.push_back(std::move(first));
  do {
    newlines();
    chain->children.push_back(clause());
  } while (take(","));
  finish(*chain);
  owner.children.push_back(std::move(chain));
}

std::unique_ptr<Node> Parser::stmt() {
  auto start = peek().span;
  if (is("let") || is("var")) {
    bool mutableBinding = take("var");
    if (!mutableBinding) {
      expect("let");
      if (is("mut"))
        fail("`let mut` is not valid syntax", "parse",
             {{"help", {}, "use `var` for a mutable local binding"}});
    }
    auto result = node(Kind::Binding, start);
    result->flag = mutableBinding;
    if (is("(") || is("[") || is("none") || is("present") || is("success") ||
        is("failure") ||
        ((peek().kind == TokenKind::Word ||
          peek().kind == TokenKind::QuotedWord) &&
         (peek(1).text == "." || peek(1).text == "{"))) {
      result->patterns.push_back(pattern());
      result->text = "<pattern>";
    } else if (take("_"))
      result->text = "_";
    else {
      auto identifier = name();
      result->text = identifier.text;
      result->context = identifier.context;
    }
    if (result->text == "_" && mutableBinding)
      fail("discard uses 'let _ = expression'");
    if (take(":"))
      result->annotation = type();
    if (take("=")) {
      newlines();
      result->children.push_back(expr());
      if (take("else")) {
        newlines();
        result->children.push_back(block());
      }
    }
    if (result->children.empty() &&
        (result->annotation.empty() || result->text == "_"))
      fail("binding requires an initializer or a declared type");
    finish(*result);
    return result;
  }
  for (auto [word, kind] : {std::pair{"return", Kind::Return},
                            {"break", Kind::Break},
                            {"continue", Kind::Continue}}) {
    if (take(word)) {
      auto result = node(kind, start);
      if (kind != Kind::Return && take("label")) {
        result->label = name().text;
        result->span.end = tokens[position - 1].span.end;
      }
      if (kind != Kind::Continue && !is("}") && !is(";") &&
          peek().kind != TokenKind::Newline && peek().kind != TokenKind::End)
        result->children.push_back(expr());
      if (kind == Kind::Continue && !is("}") && !is(";") &&
          peek().kind != TokenKind::Newline && peek().kind != TokenKind::End)
        fail("continue cannot carry a value");
      finish(*result);
      return result;
    }
  }
  auto result = expr();
  if (isAssignmentOperator(peek().text)) {
    auto assignment = node(Kind::Assign, start, tokens[position++].text);
    assignment->children.push_back(std::move(result));
    newlines();
    assignment->children.push_back(expr());
    finish(*assignment);
    return assignment;
  }
  return result;
}
std::unique_ptr<Node> Parser::loopExpression() {
  auto start = peek().span;
  std::string label;
  if (take("label")) {
    label = name().text;
    expect(":");
    newlines();
  }
  if (is("for")) {
    auto result = primary();
    result->label = std::move(label);
    result->span.begin = start.begin;
    return result;
  }
  bool loop = take("loop");
  if (!loop && !is("while"))
    fail("a label must introduce a loop");
  if (!loop)
    expect("while");
  auto result = node(loop ? Kind::Loop : Kind::While, start);
  result->label = std::move(label);
  if (!loop)
    conditions(*result);
  newlines();
  result->children.push_back(block());
  finish(*result);
  return result;
}
} // namespace mettle::parsing
