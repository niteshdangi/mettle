#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::unique_ptr<Node> Parser::stmt() {
  auto start = peek().span;
  if (is("let") || is("var")) {
    bool mutableBinding = take("var");
    if (!mutableBinding)
      expect("let");
    auto result = node(Kind::Binding, start);
    result->flag = mutableBinding;
    result->text = take("_") ? "_" : name().text;
    if (result->text == "_" && mutableBinding)
      fail("discard uses 'let _ = expression'");
    if (take(":"))
      result->annotation = type();
    if (take("=")) {
      newlines();
      result->children.push_back(expr());
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
      if (kind == Kind::Return && !is("}") && !is(";") &&
          peek().kind != TokenKind::Newline && peek().kind != TokenKind::End)
        result->children.push_back(expr());
      if (kind != Kind::Return && !is("}") && !is(";") &&
          peek().kind != TokenKind::Newline && peek().kind != TokenKind::End)
        feature("loop labels and break values require I04");
      finish(*result);
      return result;
    }
  }
  if (is("while") || is("loop")) {
    bool loop = take("loop");
    if (!loop)
      expect("while");
    auto result = node(loop ? Kind::Loop : Kind::While, start);
    if (!loop)
      result->children.push_back(expr());
    newlines();
    result->children.push_back(block());
    finish(*result);
    return result;
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
} // namespace mettle::parsing
