#include "syntax/lexer.h"
#include "syntax/parser/detail.h"
#include <utility>

namespace mettle::parsing {
// `T.(Interface).member` builds the node of `<T implements Interface>::member`.
std::unique_ptr<Node> Parser::interfaceMember(std::unique_ptr<Node> subject) {
  TypeSyntax receiver;
  if (subject->kind == Kind::Name &&
      subject->annotation.form == TypeForm::Named &&
      subject->ownerGenericArguments.empty())
    receiver.name = subject->text;
  else if (auto owner = subject->kind == Kind::Field && !subject->flag
                            ? dottedPath(*subject->children[0])
                            : std::nullopt)
    receiver.name = *owner + "::" + subject->text;
  else
    fail("expected a type name before '.('");
  receiver.arguments = subject->genericArguments;
  for (const auto &argument : receiver.arguments)
    if (!argument.region.empty())
      receiver.regions.push_back(argument.region);
  ++position;
  expect("(");
  ++parens;
  auto interface = boundType();
  expect(")");
  --parens;
  expect(".");
  auto member = name();
  auto result = node(Kind::Name, subject->span, member.text);
  result->annotation.form = TypeForm::Projection;
  result->annotation.name = member.text;
  result->annotation.elements.push_back(std::move(receiver));
  result->annotation.elements.push_back(std::move(interface));
  result->span.end = member.span.end;
  return result;
}
// `[T].(Interface).member` names a slice-type member, never an array literal.
bool Parser::sliceInterfaceMember() const {
  int depth = 0;
  for (auto index = position; index < tokens.size(); ++index) {
    const auto &text = tokens[index].text;
    if (text == "[")
      ++depth;
    else if (text == "]" && --depth == 0)
      return index + 2 < tokens.size() && tokens[index + 1].text == "." &&
             tokens[index + 2].text == "(";
  }
  return false;
}
std::unique_ptr<Node> Parser::expr(int minimum) {
  StateGuard guard(*this);
  if (++nesting > limits::parserNesting)
    fail("expression nesting limit exceeded", "limit");
  std::unique_ptr<Node> left;
  if (minimum <= 1 && (is("..") || is("..="))) {
    auto operation = tokens[position++];
    left = node(Kind::Range, operation.span, operation.text);
    if (rangeEnds()) {
      if (operation.text == "..=")
        fail("an inclusive range requires an upper bound");
      left->name = "full";
    } else {
      left->name = "to";
      left->children.push_back(expr(2));
    }
    finish(*left);
    if (is("..") || is("..="))
      fail("ranges do not chain");
    --nesting;
    return left;
  }
  left = primary();
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
    const bool range = operation.text == ".." || operation.text == "..=";
    if (range && rangeEnds()) {
      if (operation.text == "..=")
        fail("an inclusive range requires an upper bound");
      auto result = node(Kind::Range, left->span, operation.text);
      result->name = "from";
      result->children.push_back(std::move(left));
      finish(*result);
      if (is("..") || is("..="))
        fail("ranges do not chain");
      left = std::move(result);
      continue;
    }
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
// An f-string is a recipe call built by `formatRecipe`; the checker accepts
// it only as the argument of a `format` parameter.
std::unique_ptr<Node> Parser::formatString() {
  const auto open = tokens[position++];
  std::vector<std::unique_ptr<Node>> holes, pieces;
  auto at = [&]() -> const Token & {
    return tokens[std::min(position, tokens.size() - 1)];
  };
  auto literal = [&](const std::string &text, Span span) {
    textSpans.push_back(span);
    return node(Kind::Text, span, "\"" + text + "\"");
  };
  std::string text;
  Span span{open.span.end, open.span.end, open.span.source};
  for (;;) {
    const auto &token = at();
    if (token.kind == TokenKind::FormatPiece) {
      text = token.text;
      span = token.span;
      ++position;
    } else if (token.kind == TokenKind::FormatHoleOpen) {
      pieces.push_back(literal(text, span));
      text.clear();
      span = {token.span.end, token.span.end, token.span.source};
      ++position;
      ++parens;
      holes.push_back(expr());
      if (at().kind != TokenKind::FormatHoleClose)
        fail("expected '}' to close the interpolation");
      ++position;
      --parens;
    } else if (token.kind == TokenKind::FormatClose) {
      pieces.push_back(literal(text, span));
      ++position;
      break;
    } else
      fail("expected '}' to close the interpolation");
  }
  return formatRecipe(
      {open.span.begin, tokens[position - 1].span.end, open.span.source},
      std::move(holes), std::move(pieces));
}
std::unique_ptr<Node> Parser::primary() {
  StateGuard guard(*this);
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
  else if (is("[") && sliceInterfaceMember()) {
    auto projection = type(false);
    if (projection.form != TypeForm::Projection)
      fail("expected an interface member after a slice type");
    result = node(Kind::Name, token.span, projection.name);
    result->annotation = std::move(projection);
    result->span.end = tokens[position - 1].span.end;
  } else if (take("[")) {
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
    loopHeadParens = parens;
    result->children.push_back(expr());
    loopHeadParens.reset();
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
    result->children.push_back(kind == Kind::Throw ? expr(1) : primary());
  } else if (is("await")) {
    if (!inAsyncBody)
      fail("`await` is only valid inside an async function body");
    ++position;
    newlines();
    result = awaitExpression(NodeOwner(primary()), token.span);
  } else if (is("heap") || is("shared") || is("weak") ||
             (is("local") && peek(1).text == "shared")) {
    const auto operation = tokens[position++];
    std::string constructor;
    bool downgrade = operation.text == "weak";
    if (operation.text == "heap")
      constructor = "alloc::boxed::new";
    else if (operation.text == "shared")
      constructor = "alloc::arc::new";
    else if (operation.text == "local") {
      expect("shared");
      constructor = "alloc::rc::new";
    }
    newlines();
    auto operand = primary();
    result = node(Kind::Call, operation.span);
    if (downgrade) {
      auto member = node(Kind::Field, operation.span, "downgrade");
      member->children.push_back(std::move(operand));
      finish(*member);
      result->children.push_back(std::move(member));
    } else {
      result->children.push_back(
          node(Kind::Name, operation.span, std::move(constructor)));
      result->children.push_back(std::move(operand));
    }
    finish(*result);
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
  } else if (token.kind == TokenKind::FormatOpen) {
    result = formatString();
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
  } else if (token.kind == TokenKind::Text ||
             token.kind == TokenKind::PrefixedText) {
    ++position;
    result = node(Kind::Text, token.span, token.text);
    result->flag = token.text.front() == 'b';
    textSpans.push_back(token.span);
  } else if (take("true") || take("false")) {
    result = node(Kind::Boolean, token.span, token.text);
  } else {
    if (token.kind == TokenKind::Word) {
      if (isUnsupportedExpressionWord(token.text)) {
        if (rejectedNames.contains(token.text))
          throw ParseFailure{};
        feature("this language feature is not implemented yet");
      }
    }
    if (token.kind != TokenKind::Word && token.kind != TokenKind::QuotedWord)
      fail("expected an expression");
    auto identifier = name();
    result = node(Kind::Name, identifier.span, identifier.text);
    // A dotted path ending in `!` names a macro (`core.arch.asm!`).
    auto end = position;
    while (tokens[end].text == "." && nameToken(tokens[end + 1]))
      end += 2;
    if (end != position && tokens[end].text == "!")
      while (position != end) {
        ++position;
        auto segment = tokens[position++];
        result->text += "::" + segment.text;
        result->span.end = segment.span.end;
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
  // A name just specialized with `<...>`: a following `.member` continues a
  // type-qualified path (`List<T>.new`).
  bool specialized = false;
  for (;;) {
    const bool qualifies = std::exchange(specialized, false);
    if (is("<") &&
        (result->kind == Kind::Name || result->kind == Kind::Field) &&
        result->genericArguments.empty()) {
      std::vector<GenericArgument> arguments;
      if (genericApplication(arguments)) {
        result->genericArguments = std::move(arguments);
        result->span.end = tokens[position - 1].span.end;
        specialized =
            result->kind == Kind::Name && result->ownerGenericArguments.empty();
        continue;
      }
    }
    if (qualifies && is(".") && nameToken(peek(1))) {
      ++position;
      auto member = is("drop") ? tokens[position++] : name();
      result->text += "::" + member.text;
      result->span.end = member.span.end;
      result->ownerGenericArguments = std::move(result->genericArguments);
      result->genericArguments.clear();
      continue;
    }
    if (is(".") && peek(1).text == "(") {
      result = interfaceMember(std::move(result));
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
  finish(*result);
  --nesting;
  return result;
}
} // namespace mettle::parsing
