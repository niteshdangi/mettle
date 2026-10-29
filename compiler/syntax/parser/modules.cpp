#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::vector<std::string> Parser::path() {
  std::vector<std::string> result{name().text};
  while (is("::") && peek(1).text != "{" && peek(1).text != "*") {
    ++position;
    result.push_back(name().text);
  }
  return result;
}

VisibilitySyntax Parser::visibility() {
  VisibilitySyntax result;
  if (!take("pub"))
    return result;
  result.publicItem = true;
  result.span = tokens[position - 1].span;
  if (take("(")) {
    ++parens;
    result.restriction = path();
    result.span.end = expect(")").span.end;
    --parens;
  }
  return result;
}

void Parser::moduleDeclaration(Module &module, ItemSyntax item) {
  Module::ModuleDeclaration declaration;
  declaration.span = expect("module").span;
  declaration.name = name().text;
  declaration.item = std::move(item);
  auto child = declaration.item.scope;
  child.push_back(declaration.name);
  auto end = tokens[position - 1].span.end;
  auto beforeNewline = position;
  newlines();
  bool separated = position != beforeNewline;
  if (take("{")) {
    if (++nesting > limits::parserNesting)
      fail("module nesting limit exceeded", "limit");
    run(module, std::move(child), true);
    declaration.span.end = expect("}").span.end;
    --nesting;
  } else {
    declaration.external = true;
    declaration.span.end = end;
    if (!take(";") && !separated && peek().kind != TokenKind::Newline &&
        peek().kind != TokenKind::End && !is("}"))
      fail("expected ';' or a newline after an external module");
  }
  module.modules.push_back(std::move(declaration));
}

void Parser::importDeclaration(Module &module, ItemSyntax item) {
  Module::Import declaration;
  declaration.span = expect("import").span;
  declaration.item = std::move(item);
  declaration.path = path();
  if (take("as")) {
    declaration.alias = name().text;
  } else if (take("::")) {
    if (take("*")) {
      declaration.glob = true;
    } else {
      expect("{");
      newlines();
      if (is("}"))
        fail("an import group requires at least one name");
      do {
        newlines();
        if (is("}"))
          break;
        auto token = name();
        Module::Import::Name entry{token.text, "", token.span};
        if (take("as"))
          entry.alias = name().text;
        declaration.names.push_back(std::move(entry));
        newlines();
      } while (take(","));
      expect("}");
    }
  }
  declaration.span.end = tokens[position - 1].span.end;
  if (peek().kind != TokenKind::Newline && !is(";") && !is("}") &&
      peek().kind != TokenKind::End)
    fail("expected a newline or ';' after an import");
  module.imports.push_back(std::move(declaration));
}
} // namespace mettle::parsing
