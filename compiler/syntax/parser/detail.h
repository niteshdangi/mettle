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
            tokens.push_back({TokenKind::Newline,
                              {token.span.begin + i,
                               token.span.begin + i + size, token.span.source},
                              "\n"});
            i += size - 1;
          }
      }
    }
  }

  void run(Module &module, std::vector<std::string> scope = {},
           bool nested = false);

private:
  std::vector<Token> tokens;
  Diagnostics &diagnostics;
  std::size_t position = 0;
  unsigned parens = 0, nesting = 0;
  unsigned genericExpressionLevel = 0;
  VisibilitySyntax visibility();
  std::vector<Attribute> attributes();
  std::string textLiteral();
  void foreignDeclaration(Module &module, ItemSyntax item);
  void staticDeclaration(Module &module, ItemSyntax item, bool foreign);
  std::vector<std::string> path();
  void moduleDeclaration(Module &module, ItemSyntax item);
  void importDeclaration(Module &module, ItemSyntax item);

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
    if ((result.kind != TokenKind::Word &&
         result.kind != TokenKind::QuotedWord) ||
        (result.kind != TokenKind::QuotedWord && isReservedWord(result.text)))
      fail("expected an identifier");
    ++position;
    if (result.kind == TokenKind::QuotedWord)
      result.text = result.text.substr(1, result.text.size() - 2);
    return result;
  }
  TypeSyntax type(bool effect = true);
  TypeSyntax boundType();
  TypeSyntax callableType();
  std::unique_ptr<Node> closure();
  std::vector<GenericParameter>
  genericParameters(std::vector<std::string> *regions = nullptr);
  std::vector<GenericArgument> genericArguments();
  std::vector<GenericConstraint> genericConstraints();
  bool genericClose();
  std::shared_ptr<const Node> genericValue();
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
  Function function(bool allowDeclaration = false);
  std::unique_ptr<Node> loopExpression();
  Module::Product product();
  Module::Product enumeration();
  Module::Interface interfaceDeclaration();
  Module::Implementation implementationDeclaration();
  Module::Associated associatedDeclaration();
  Pattern pattern(int minimum = 0);
  std::unique_ptr<Node> matchExpression();
  std::unique_ptr<Node> block();
  std::unique_ptr<Node> stmt();

  std::unique_ptr<Node> expr(int minimum = 1);
  std::unique_ptr<Node> primary();
  std::unique_ptr<Node> assemblyExpression(std::string variant, Span span);
};
} // namespace mettle::parsing
