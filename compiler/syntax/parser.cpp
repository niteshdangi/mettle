#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
void Parser::run(Module &module) {
  separators();
  while (peek().kind != TokenKind::End) {
    try {
      if (is("type") || is("copy")) {
        module.products.push_back(product());
        if (module.products.size() > limits::products)
          fail("product declaration limit exceeded", "limit");
      } else {
        if (!is("fn"))
          feature("this declaration is not implemented");
        module.functions.push_back(function());
        if (module.functions.size() > limits::functions)
          fail("function limit exceeded", "limit");
      }
    } catch (ParseFailure &) {
      parens = nesting = 0;
      while (peek().kind != TokenKind::End && !is("fn") && !is("type") &&
             !is("copy"))
        ++position;
    }
    separators();
  }
}
} // namespace mettle::parsing

namespace mettle {
Module parse(const Source &source, Diagnostics &diagnostics) {
  Module module;
  module.tokens = tokenize(source, diagnostics);
  if (diagnostics.empty())
    parsing::Parser(module.tokens, diagnostics).run(module);
  for (auto &product : module.products) {
    for (auto &method : product.methods)
      module.functions.push_back(std::move(method));
    product.methods.clear();
  }
  return module;
}
} // namespace mettle
