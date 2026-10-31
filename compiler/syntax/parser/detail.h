#pragma once
#include "support/limits.h"
#include "syntax/parser.h"
#include <optional>
#include <set>
#include <tuple>

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
  const std::vector<Span> &textLiterals() const { return textSpans; }

private:
  std::vector<Token> tokens;
  Diagnostics &diagnostics;
  std::size_t position = 0;
  unsigned parens = 0, nesting = 0;
  // Paren depth of the enclosing `for` head, whose body block ends a range.
  std::optional<unsigned> loopHeadParens{};
  // Reserved words already rejected as names, so later uses stay silent.
  std::set<std::string> rejectedNames;
  std::optional<std::size_t> failedAt;
  std::vector<Span> textSpans;
  unsigned genericExpressionLevel = 0;
  // Speculative parsing (generic application): failures are silent and
  // in-place token splits are journaled so they can be undone.
  bool speculating = false;
  struct TokenEdit {
    std::size_t index;
    Token before;
    bool inserted;
  };
  std::vector<TokenEdit> tokenEdits;
  // Rejected applications by (position, token count, parens, `>>` level).
  std::set<std::tuple<std::size_t, std::size_t, unsigned, unsigned>>
      rejectedApplications;
  // Parsing the body of an `async fn`, where `await` is accepted.
  bool inAsyncBody = false;
  // Numbers the temporaries that hoisting an `await` introduces.
  unsigned awaitTemporaries = 0;
  // `async` consumed by a member dispatcher ahead of its receiver mode.
  bool pendingAsync = false;
  struct StateGuard {
    Parser &parser;
    unsigned parens, nesting, genericExpressionLevel;
    std::optional<unsigned> loopHeadParens;
    explicit StateGuard(Parser &parser)
        : parser(parser), parens(parser.parens), nesting(parser.nesting),
          genericExpressionLevel(parser.genericExpressionLevel),
          loopHeadParens(parser.loopHeadParens) {}
    ~StateGuard() {
      parser.parens = parens;
      parser.loopHeadParens = loopHeadParens;
      parser.nesting = nesting;
      parser.genericExpressionLevel = genericExpressionLevel;
    }
  };
  VisibilitySyntax visibility();
  std::vector<Attribute> attributes();
  std::string textLiteral();
  void foreignDeclaration(Module &module, ItemSyntax item);
  void staticDeclaration(Module &module, ItemSyntax item, bool foreign);
  std::vector<std::string> path();
  void moduleDeclaration(Module &module, ItemSyntax item);
  void importDeclaration(Module &module, ItemSyntax item);

  const Token &peek(std::size_t look = 0) {
    position = std::min(position, tokens.size() - 1);
    if (parens)
      while (position + 1 < tokens.size() &&
             tokens[position].kind == TokenKind::Newline)
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
    // Recovery that fails again at the same token is a cascade, not news.
    if (speculating)
      throw ParseFailure{};
    auto span = peek().span;
    if (!failedAt || *failedAt != span.begin)
      diagnostics.error(std::move(phase), span, std::move(message));
    failedAt = span.begin;
    throw ParseFailure{};
  }
  [[noreturn]] void feature(std::string message) {
    fail(std::move(message), "feature");
  }
  // A range operator with no operand after it ends the expression.
  bool rangeEnds() {
    auto &next = peek();
    return next.kind == TokenKind::Newline || next.kind == TokenKind::End ||
           next.text == "]" || next.text == ")" || next.text == "," ||
           next.text == "}" || next.text == ";" || next.text == "=>" ||
           (next.text == "{" && loopHeadParens == parens);
  }
  void newlines() {
    while (peek().kind == TokenKind::Newline)
      ++position;
  }
  // An item ends at a newline, `}`, end of input or an optional `;`.
  void endItem(const char *what) {
    if (take(";") || peek().kind == TokenKind::Newline ||
        peek().kind == TokenKind::End || is("}"))
      return;
    fail(std::string("expected a newline after ") + what);
  }
  void separators() {
    while (peek().kind == TokenKind::Newline || is(";"))
      ++position;
  }
  Token name() {
    auto result = peek();
    if ((result.kind != TokenKind::Word &&
         result.kind != TokenKind::QuotedWord) ||
        (result.kind != TokenKind::QuotedWord && isReservedWord(result.text))) {
      if (result.kind == TokenKind::Word)
        rejectedNames.insert(result.text);
      fail("expected an identifier");
    }
    ++position;
    if (result.kind == TokenKind::QuotedWord)
      result.text = result.text.substr(1, result.text.size() - 2);
    return result;
  }
  TypeSyntax type(bool effect = true);
  TypeSyntax boundType();
  TypeSyntax callableType();
  std::unique_ptr<Node> closure();
  std::unique_ptr<Node> interfaceMember(std::unique_ptr<Node> subject);
  bool sliceInterfaceMember() const;
  bool nameToken(const Token &token) const {
    return token.kind == TokenKind::Word || token.kind == TokenKind::QuotedWord;
  }
  bool isExtension() {
    return is("extend") || (is("unsafe") && peek(1).text == "extend");
  }
  std::vector<GenericParameter>
  genericParameters(std::vector<std::string> *regions = nullptr);
  std::vector<GenericArgument> genericArguments();
  std::vector<GenericConstraint> genericConstraints();
  bool genericApplication(std::vector<GenericArgument> &arguments);
  bool followsGenericApplication();
  void undoTokenEdits(std::size_t keep);
  bool genericClose();
  bool genericOpen();
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
  void lowerAsync(Function &function);
  // The future expression for an async body; `result` is empty when inferred.
  std::unique_ptr<Node> asyncBody(NodeOwner body, TypeSyntax result, Span span,
                                  TypeSyntax error = {});
  TypeSyntax asyncResult(TypeSyntax result, bool unitIfEmpty);
  std::unique_ptr<Node> awaitExpression(NodeOwner operand, Span span);
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
  std::unique_ptr<Node> formatString();
  std::unique_ptr<Node> assemblyExpression(std::string variant, Span span);
};
} // namespace mettle::parsing
