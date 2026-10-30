#include "syntax/parser/detail.h"
#include <charconv>

namespace mettle::parsing {
std::string Parser::textLiteral() {
  auto token = peek();
  if (token.kind != TokenKind::Text)
    fail("expected a constant text literal");
  std::string result;
  for (std::size_t i = 1; i + 1 < token.text.size(); ++i) {
    auto character = token.text[i];
    if (character != '\\') {
      result += character;
      continue;
    }
    if (++i + 1 >= token.text.size())
      fail("incomplete text escape", "lex");
    character = token.text[i];
    if (character == '\\' || character == '"')
      result += character;
    else if (character == 'n')
      result += '\n';
    else if (character == 'r')
      result += '\r';
    else if (character == 't')
      result += '\t';
    else if (character == '0')
      result += '\0';
    else if (character == 'x') {
      if (i + 3 >= token.text.size())
        fail("incomplete byte escape", "lex");
      unsigned value = 0;
      auto parsed = std::from_chars(token.text.data() + i + 1,
                                    token.text.data() + i + 3, value, 16);
      if (parsed.ec != std::errc{} || parsed.ptr != token.text.data() + i + 3 ||
          value > 127)
        fail("text byte escape requires an ASCII value", "lex");
      result += static_cast<char>(value);
      i += 2;
    } else
      fail("unsupported constant text escape", "lex");
  }
  ++position;
  return result;
}
std::vector<Attribute> Parser::attributes() {
  std::vector<Attribute> result;
  while (take("@")) {
    Attribute attribute;
    attribute.span = tokens[position - 1].span;
    if (peek().kind != TokenKind::Word && peek().kind != TokenKind::QuotedWord)
      fail("expected an attribute name");
    auto token = tokens[position++];
    attribute.name = token.kind == TokenKind::QuotedWord
                         ? token.text.substr(1, token.text.size() - 2)
                         : token.text;
    if (take("(")) {
      attribute.parenthesized = true;
      unsigned depth = 1;
      while (depth && peek().kind != TokenKind::End) {
        auto value = tokens[position++];
        if (value.text == "(")
          ++depth;
        if (value.text == ")")
          --depth;
        if (depth && value.kind != TokenKind::Newline)
          attribute.arguments.push_back(std::move(value));
      }
      if (depth)
        fail("unterminated attribute arguments");
    }
    attribute.span.end = tokens[position - 1].span.end;
    result.push_back(std::move(attribute));
    newlines();
  }
  return result;
}
void Parser::foreignDeclaration(Module &module, ItemSyntax item) {
  auto unsafe = take("unsafe");
  expect("extern");
  auto abi = textLiteral();
  newlines();
  if (take("{")) {
    separators();
    while (!is("}") && peek().kind != TokenKind::End) {
      auto metadata = attributes();
      auto visible = visibility();
      metadata.insert(metadata.begin(), item.attributes.begin(),
                      item.attributes.end());
      if (is("static")) {
        staticDeclaration(module,
                          {item.scope, std::move(visible), std::move(metadata)},
                          true);
        separators();
        continue;
      }
      auto declaration = function(true);
      if (declaration.body.get())
        fail("foreign declaration blocks cannot contain function bodies");
      declaration.abi = abi;
      declaration.unsafeFunction |= unsafe;
      declaration.foreignDeclaration = true;
      declaration.item = {item.scope, std::move(visible), std::move(metadata)};
      module.functions.push_back(std::move(declaration));
      separators();
    }
    expect("}");
    return;
  }
  auto declaration = function(true);
  declaration.abi = std::move(abi);
  declaration.unsafeFunction |= unsafe;
  declaration.foreignDeclaration = !declaration.body.get();
  declaration.item = std::move(item);
  module.functions.push_back(std::move(declaration));
}
void Parser::staticDeclaration(Module &module, ItemSyntax item, bool foreign) {
  Module::Static declaration;
  const bool constant = is("const");
  declaration.span = expect(constant ? "const" : "static").span;
  declaration.constant = constant;
  declaration.mutableBinding = !constant && take("mut");
  declaration.name = name().text;
  expect(":");
  declaration.annotation = type();
  declaration.item = std::move(item);
  declaration.foreignDeclaration = foreign;
  if (!foreign) {
    expect("=");
    newlines();
    declaration.initializer = expr();
  }
  declaration.span.end = expect(";").span.end;
  module.statics.push_back(std::move(declaration));
  if (module.statics.size() > limits::products)
    fail("static declaration limit exceeded", "limit");
}
} // namespace mettle::parsing
