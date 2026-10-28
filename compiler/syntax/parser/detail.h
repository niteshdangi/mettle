#pragma once
#include "support/limits.h"
#include "syntax/parser.h"

namespace mettle::parsing {
struct ParseFailure {};

class Parser {
public:
  Parser(const std::vector<Token> &raw, Diagnostics &diagnostics)
      : diagnostics(diagnostics) {
    for (const auto &token : raw) {
      if (token.kind == TokenKind::Space)
        continue;
      if (token.kind != TokenKind::Comment) {
        tokens.push_back(token);
      } else {
        for (std::size_t i = 0; i < token.text.size(); ++i)
          if (token.text[i] == '\n' || token.text[i] == '\r') {
            auto size = token.text[i] == '\r' && i + 1 < token.text.size() &&
                                token.text[i + 1] == '\n'
                            ? 2u
                            : 1u;
            tokens.push_back(
                {TokenKind::Newline,
                 {token.span.begin + i, token.span.begin + i + size},
                 "\n"});
            i += size - 1;
          }
      }
    }
  }

  void run(Module &module);

private:
  std::vector<Token> tokens;
  Diagnostics &diagnostics;
  std::size_t position = 0;
  unsigned parens = 0, nesting = 0;

  const Token &peek(std::size_t look = 0) {
    if (parens)
      while (tokens[position].kind == TokenKind::Newline)
        ++position;
    auto index = position;
    while (look && index + 1 < tokens.size()) {
      ++index;
      if (!parens || tokens[index].kind != TokenKind::Newline)
        --look;
    }
    return tokens[index];
  }
  bool is(std::string_view text) { return peek().text == text; }
  bool take(std::string_view text) {
    if (!is(text))
      return false;
    ++position;
    return true;
  }
  Token expect(std::string_view text) {
    if (!is(text))
      fail("expected '" + std::string(text) + "'");
    return tokens[position++];
  }
  [[noreturn]] void fail(std::string message, std::string phase = "parse") {
    diagnostics.error(std::move(phase), peek().span, std::move(message));
    throw ParseFailure{};
  }
  [[noreturn]] void feature(std::string message) {
    fail(std::move(message), "feature");
  }
  void newlines() {
    while (peek().kind == TokenKind::Newline)
      ++position;
  }
  void separators() {
    while (peek().kind == TokenKind::Newline || is(";"))
      ++position;
  }
  Token name() {
    auto result = peek();
    if (result.kind != TokenKind::Word || isReservedWord(result.text))
      fail("expected an identifier");
    ++position;
    return result;
  }
  TypeSyntax type() {
    TypeSyntax result;
    if (is("read") || is("mut"))
      result.view = tokens[position++].text;
    if (is("take") || is("heap") || is("shared"))
      feature("owning runtime handle types are not implemented yet");
    if (is("(") && peek(1).text == ")")
      fail("use Unit in type positions; () is a value");
    if (take("(")) {
      ++parens;
      auto grouped = type();
      if (is(","))
        feature("tuple types require their aggregate implementation");
      expect(")");
      --parens;
      if (result.view.empty())
        return grouped;
      result.nested = std::make_shared<const TypeSyntax>(std::move(grouped));
    } else {
      if (is("[") || is("fn"))
        feature("aggregate and callable types are not implemented in I02");
      result.name = name().text;
    }
    if (take("<")) {
      do {
        expect("region");
        result.regions.push_back(name().text);
      } while (take(","));
      expect(">");
    }
    if (take("from")) {
      bool grouped = take("(");
      do {
        result.sources.push_back(name().text);
      } while (grouped && take(","));
      if (grouped)
        expect(")");
    }
    if (is("?") || is("::"))
      feature("extended types are not implemented in I02");
    return result;
  }
  std::unique_ptr<Node> node(Kind kind, Span span, std::string text = "") {
    auto result = std::make_unique<Node>();
    result->kind = kind;
    result->span = span;
    result->text = std::move(text);
    return result;
  }
  void finish(Node &value) {
    for (const auto &child : value.children) {
      value.depth = std::max(value.depth, child->depth + 1);
      value.span.end = std::max(value.span.end, child->span.end);
    }
    if (value.depth > limits::syntaxDepth)
      fail("syntax nesting limit exceeded", "limit");
  }
  Function function();
  Module::Product product();
  std::unique_ptr<Node> block();
  std::unique_ptr<Node> stmt();

  std::unique_ptr<Node> expr(int minimum = 1);
  std::unique_ptr<Node> primary();
};
} // namespace mettle::parsing
