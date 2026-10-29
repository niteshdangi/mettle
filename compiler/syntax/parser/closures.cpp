#include "syntax/parser/detail.h"

namespace mettle::parsing {
TypeSyntax Parser::callableType() {
  auto callable = std::make_shared<CallableTypeSyntax>();
  if (take("for")) {
    expect("<");
    do {
      if (is(">"))
        break;
      expect("region");
      callable->regions.push_back(name().text);
    } while (take(","));
    expect(">");
  }
  callable->unsafeCall = take("unsafe");
  if (take("extern"))
    callable->abi = textLiteral();
  if (is("async"))
    feature("async callables require task lowering");
  if (is("mut") || is("take"))
    callable->mode = tokens[position++].text;
  expect("fn");
  expect("(");
  ++parens;
  if (!is(")"))
    do {
      if (is(")"))
        break;
      if (take("...")) {
        callable->variadic = true;
        break;
      }
      CallableParameterSyntax parameter;
      if (is("read") || is("mut") || is("take"))
        parameter.mode = tokens[position++].text;
      parameter.annotation = type();
      callable->parameters.push_back(std::move(parameter));
    } while (take(","));
  expect(")");
  --parens;
  expect(":");
  callable->result = type(false);
  if (take("throws"))
    callable->error = type();
  TypeSyntax result;
  result.form = TypeForm::Callable;
  result.callable = std::move(callable);
  return result;
}
std::unique_ptr<Node> Parser::closure() {
  auto start = peek();
  if (take("async"))
    feature("async closures require I06");
  auto result = node(Kind::Closure, start.span);
  result->flag = take("take");
  expect("fn");
  expect("(");
  ++parens;
  if (!is(")"))
    do {
      if (is(")"))
        break;
      ClosureParameter parameter;
      parameter.span = peek().span;
      auto binding = pattern(2);
      if (binding.kind == PatternKind::Binding)
        parameter.name = binding.text;
      else {
        parameter.name = "<closure-parameter-" +
                         std::to_string(result->parameters.size()) + ">";
        parameter.pattern = std::move(binding);
      }
      if (take(":")) {
        if (is("read") || is("mut") || is("take"))
          parameter.mode = tokens[position++].text;
        parameter.annotation = type();
      }
      result->parameters.push_back(std::move(parameter));
    } while (take(","));
  expect(")");
  --parens;
  if (take(":"))
    result->annotation = type(false);
  if (take("throws"))
    result->error = type();
  newlines();
  result->children.push_back(block());
  finish(*result);
  return result;
}
} // namespace mettle::parsing
