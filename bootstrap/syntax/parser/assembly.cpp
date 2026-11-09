#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::unique_ptr<Node> Parser::assemblyExpression(std::string variant,
                                                 Span span) {
  StateGuard guard(*this);
  auto result = node(Kind::Assembly, span);
  result->assembly.emplace();
  auto &assembly = *result->assembly;
  assembly.variant = std::move(variant);
  expect("!");
  expect("(");
  ++parens;
  bool operands = false;
  while (!is(")") && peek().kind != TokenKind::End) {
    if (peek().kind == TokenKind::Text) {
      if (operands)
        fail("assembly templates must precede operands");
      assembly.templates.push_back(textLiteral());
    } else if (is("options") || is("clobber_abi")) {
      operands = true;
      bool options = take("options");
      if (!options)
        expect("clobber_abi");
      auto &values = options ? assembly.options : assembly.clobberAbis;
      expect("(");
      while (!is(")")) {
        auto value = options ? name().text : textLiteral();
        if (std::find(values.begin(), values.end(), value) != values.end())
          fail("duplicate assembly option or clobber ABI");
        values.push_back(std::move(value));
        if (!take(","))
          break;
      }
      expect(")");
    } else {
      operands = true;
      AssemblySyntax::Operand operand;
      operand.span = peek().span;
      if (peek(1).text == "=") {
        operand.name = name().text;
        expect("=");
      }
      if (peek().kind != TokenKind::Word)
        fail("expected an assembly operand mode");
      operand.mode = tokens[position++].text;
      if (operand.mode == "const" || operand.mode == "sym") {
        operand.input = static_cast<int>(result->children.size());
        result->children.push_back(expr());
      } else {
        if (operand.mode != "in" && operand.mode != "out" &&
            operand.mode != "lateout" && operand.mode != "inout" &&
            operand.mode != "inlateout")
          fail("unknown assembly operand mode");
        expect("(");
        operand.explicitRegister = peek().kind == TokenKind::Text;
        operand.reg = operand.explicitRegister ? textLiteral() : name().text;
        expect(")");
        bool input = operand.mode == "in" || operand.mode == "inout" ||
                     operand.mode == "inlateout";
        bool output = operand.mode != "in";
        if (input) {
          operand.input = static_cast<int>(result->children.size());
          result->children.push_back(expr());
        }
        if (output) {
          if (input && !take("=>"))
            operand.output = operand.input;
          else if (take("_"))
            operand.discard = true;
          else {
            operand.output = static_cast<int>(result->children.size());
            result->children.push_back(expr());
          }
        }
      }
      operand.span.end = tokens[position - 1].span.end;
      assembly.operands.push_back(std::move(operand));
    }
    if (!take(","))
      break;
  }
  result->span.end = expect(")").span.end;
  --parens;
  finish(*result);
  return result;
}
} // namespace mettle::parsing
