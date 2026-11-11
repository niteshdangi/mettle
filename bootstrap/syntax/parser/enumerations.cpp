#include "syntax/parser/detail.h"

namespace mettle::parsing {
Module::Product Parser::enumeration() {
  Module::Product result;
  result.span = peek().span;
  result.copyRequested = take("copy");
  expect("enum");
  result.enumeration = true;
  auto identifier = name();
  result.name = identifier.text;
  result.nameContext = identifier.context;
  result.genericParameters = genericParameters(&result.regions);
  result.constraints = genericConstraints();
  newlines();
  expect("{");
  separators();
  while (!is("}") && peek().kind != TokenKind::End) {
    auto metadata = attributes();
    auto token = name();
    Module::Product::Variant variant{token.text, {}, token.span};
    variant.attributes = std::move(metadata);
    if (take("(")) {
      ++parens;
      while (!is(")")) {
        auto annotation = type();
        variant.fields.push_back({std::to_string(variant.fields.size()),
                                  std::move(annotation), token.span});
        if (!take(","))
          break;
      }
      variant.span.end = expect(")").span.end;
      --parens;
    } else if (take("{")) {
      separators();
      while (!is("}")) {
        auto fieldAttributes = attributes();
        auto field = name();
        expect(":");
        variant.fields.push_back({field.text, type(), field.span});
        variant.fields.back().syntaxSpan = Span{
            field.span.begin, tokens[position - 1].span.end, field.span.source};
        variant.fields.back().context = field.context;
        variant.fields.back().attributes = std::move(fieldAttributes);
        if (!take(",") && !is("}") && peek().kind != TokenKind::Newline &&
            !is(";"))
          fail("expected a variant field separator");
        separators();
      }
      variant.span.end = expect("}").span.end;
    }
    if (take("=")) {
      variant.discriminant = std::shared_ptr<const Node>(expr());
      variant.span.end = tokens[position - 1].span.end;
    }
    result.variants.push_back(std::move(variant));
    if (!take(",") && !is("}") && peek().kind != TokenKind::Newline && !is(";"))
      fail("expected a variant separator");
    separators();
  }
  result.span.end = expect("}").span.end;
  return result;
}
} // namespace mettle::parsing
