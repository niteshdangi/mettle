#include "syntax/lexer.h"
#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::unique_ptr<Node> Parser::expr(int minimum) {
  if (++nesting > limits::parserNesting)
    fail("expression nesting limit exceeded", "limit");
  auto left = primary();
  bool compared = false;
  while (int level = is("as") ? 12 : binaryPrecedence(peek().text)) {
    if (is("as")) {
      if (level < minimum)
        break;
      ++position;
      auto result = node(Kind::Cast, left->span);
      result->children.push_back(std::move(left));
      result->annotation = type();
      finish(*result);
      left = std::move(result);
      continue;
    }
    if (genericExpressionLevel && genericExpressionLevel == parens &&
        (is(">>") || is(">>=")))
      break;
    if (level < minimum)
      break;
    if (level == 5 && compared)
      fail("comparisons do not chain");
    compared |= level == 5;
    auto operation = tokens[position++];
    newlines();
    auto kind = operation.text == "??" ? Kind::Coalesce
                : (operation.text == ".." || operation.text == "..=")
                    ? Kind::Range
                    : Kind::Binary;
    auto result = node(kind, left->span, operation.text);
    result->children.push_back(std::move(left));
    result->children.push_back(expr(level + (kind == Kind::Coalesce ? 0 : 1)));
    if (kind == Kind::Range && (is("..") || is("..=")))
      fail("ranges do not chain");
    finish(*result);
    left = std::move(result);
  }
  --nesting;
  return left;
}
std::unique_ptr<Node> Parser::primary() {
  if (++nesting > limits::parserNesting)
    fail("expression nesting limit exceeded", "limit");
  auto token = peek();
  std::unique_ptr<Node> result;
  if (take("unsafe")) {
    result = node(Kind::Unsafe, token.span);
    newlines();
    result->children.push_back(block());
  } else if (is("fn") || is("async") || (is("take") && peek(1).text == "fn"))
    result = closure();
  else if (take("[")) {
    result = node(Kind::Array, token.span);
    ++parens;
    if (!is("]")) {
      result->children.push_back(expr());
      if (take(";")) {
        result->flag = true;
        result->children.push_back(expr());
      } else
        while (take(",") && !is("]"))
          result->children.push_back(expr());
    }
    result->span.end = expect("]").span.end;
    --parens;
  } else if (is("for")) {
    ++position;
    result = node(Kind::For, token.span);
    result->patterns.push_back(pattern());
    expect("in");
    result->children.push_back(expr());
    newlines();
    result->children.push_back(block());
  } else if (is("match"))
    result = matchExpression();
  else if (take("none"))
    result = node(Kind::None, token.span);
  else if (is("present") || is("success") || is("failure")) {
    auto variant = tokens[position++];
    result = node(Kind::Variant, variant.span, variant.text);
    expect("(");
    ++parens;
    result->children.push_back(expr());
    result->span.end = expect(")").span.end;
    --parens;
  } else if (is("try") || is("capture") || is("throw")) {
    auto operation = tokens[position++];
    auto kind = operation.text == "try"       ? Kind::Try
                : operation.text == "capture" ? Kind::Capture
                                              : Kind::Throw;
    result = node(kind, operation.span);
    result->children.push_back(expr(1));
  } else if (take("-") || take("!") || take("take") || take("read") ||
             take("mut") || take("*")) {
    result = node(Kind::Unary, token.span, token.text);
    newlines();
    result->children.push_back(primary());
  } else if (take("if")) {
    result = node(Kind::If, token.span);
    if (take("let")) {
      result->patterns.push_back(pattern());
      expect("=");
    }
    result->children.push_back(expr());
    newlines();
    result->children.push_back(block());
    auto saved = position;
    newlines();
    if (take("else")) {
      newlines();
      result->children.push_back(is("if") ? primary() : block());
    } else
      position = saved;
  } else if (is("{")) {
    result = block();
  } else if (is("while") || is("loop") || is("label")) {
    result = loopExpression();
  } else if (take("(")) {
    ++parens;
    if (take(")"))
      result =
          node(Kind::Unit, {token.span.begin, tokens[position - 1].span.end});
    else {
      result = node(Kind::Group, token.span);
      result->children.push_back(expr());
      if (take(",")) {
        result->kind = Kind::Tuple;
        while (!is(")")) {
          result->children.push_back(expr());
          if (!take(","))
            break;
        }
      }
      result->span.end = expect(")").span.end;
    }
    --parens;
  } else if (take("<")) {
    auto subject = type();
    expect("implements");
    auto interface = boundType();
    genericClose();
    expect("::");
    auto member = name();
    result = node(Kind::Name, token.span, member.text);
    result->annotation.form = TypeForm::Projection;
    result->annotation.name = member.text;
    result->annotation.elements.push_back(std::move(subject));
    result->annotation.elements.push_back(std::move(interface));
    result->span.end = member.span.end;
  } else if (token.kind == TokenKind::Character ||
             token.kind == TokenKind::Byte) {
    ++position;
    result = node(Kind::Character, token.span, token.text);
    result->flag = token.kind == TokenKind::Byte;
  } else if (token.kind == TokenKind::Integer ||
             token.kind == TokenKind::Floating) {
    ++position;
    result =
        node(token.kind == TokenKind::Integer ? Kind::Integer : Kind::Floating,
             token.span, token.text);
  } else if (take("true") || take("false")) {
    result = node(Kind::Boolean, token.span, token.text);
  } else {
    if (token.kind == TokenKind::Text)
      feature("runtime text values require the native text library");
    if (token.kind == TokenKind::Word) {
      if (isUnsupportedExpressionWord(token.text))
        feature("this language feature is not implemented yet");
    }
    auto identifier = name();
    result = node(Kind::Name, identifier.span, identifier.text);
    while (take("::")) {
      if (is("<")) {
        result->genericArguments = genericArguments();
        result->span.end = tokens[position - 1].span.end;
        if (is("::") && peek(1).text != "<")
          result->ownerGenericArguments = std::move(result->genericArguments);
        continue;
      }
      auto member = is("drop") ? tokens[position++] : name();
      result->text += "::" + member.text;
      result->span.end = member.span.end;
    }
  }
  if (result->kind == Kind::Name && is("!")) {
    auto separator = result->text.rfind("::");
    auto macro =
        result->text.substr(separator == std::string::npos ? 0 : separator + 2);
    if (macro == "asm" || macro == "naked_asm" || macro == "global_asm")
      result = assemblyExpression(macro, result->span);
    else if (macro == "is_x86_feature_detected" ||
             macro == "is_aarch64_feature_detected") {
      expect("!");
      expect("(");
      auto feature = node(Kind::FeatureTest, result->span, textLiteral());
      feature->name = macro;
      feature->span.end = expect(")").span.end;
      result = std::move(feature);
    } else
      feature("unsupported machine macro");
  }
  for (;;) {
    if (is("::") && peek(1).text == "<") {
      ++position;
      result->genericArguments = genericArguments();
      result->span.end = tokens[position - 1].span.end;
      continue;
    }
    if (take("[")) {
      auto index = node(Kind::Index, result->span);
      index->children.push_back(std::move(result));
      ++parens;
      index->children.push_back(expr());
      index->span.end = expect("]").span.end;
      --parens;
      result = std::move(index);
      continue;
    }
    bool optionalMember = is("?.");
    if (take(".") || take("?.")) {
      newlines();
      auto member =
          is("drop") || is("copy") || peek().kind == TokenKind::Integer
              ? tokens[position++]
              : name();
      auto field = node(Kind::Field, result->span, member.text);
      field->flag = optionalMember;
      field->span.end = member.span.end;
      field->children.push_back(std::move(result));
      finish(*field);
      result = std::move(field);
      continue;
    }
    if (!take("("))
      break;
    auto call = node(Kind::Call, result->span);
    call->children.push_back(std::move(result));
    ++parens;
    if (!is(")")) {
      do {
        if (is(")"))
          break;
        std::string label;
        if ((peek().kind == TokenKind::Word ||
             peek().kind == TokenKind::QuotedWord) &&
            peek(1).text == ":") {
          label = name().text;
          expect(":");
        }
        auto argument = expr();
        argument->name = label;
        call->children.push_back(std::move(argument));
      } while (take(","));
    }
    call->span.end = expect(")").span.end;
    --parens;
    finish(*call);
    result = std::move(call);
  }
  if (is("::"))
    feature("extended postfix expressions are not implemented in I02");
  finish(*result);
  --nesting;
  return result;
}
} // namespace mettle::parsing
