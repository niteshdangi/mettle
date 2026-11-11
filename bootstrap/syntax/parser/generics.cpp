#include "syntax/parser/detail.h"

namespace mettle::parsing {
std::shared_ptr<const Node> Parser::genericValue() {
  struct Restore {
    unsigned &level;
    unsigned previous;
    ~Restore() { level = previous; }
  } restore{genericExpressionLevel, genericExpressionLevel};
  if (take("{")) {
    genericExpressionLevel = 0;
    auto value = expr();
    expect("}");
    return std::shared_ptr<const Node>(std::move(value));
  }
  genericExpressionLevel = parens;
  return std::shared_ptr<const Node>(expr(6));
}
bool Parser::genericClose() {
  if (take(">"))
    return true;
  if (is(">>") || is(">=") || is(">>=")) {
    auto &token = tokens[position];
    if (speculating)
      tokenEdits.push_back({position, token, false});
    token.text.erase(token.text.begin());
    ++token.span.begin;
    return true;
  }
  return false;
}
// A `<<` directly before a projection (`Vec<<T implements I>::Item>`) is two
// opening brackets in a type-argument context; split it in place.
bool Parser::genericOpen() {
  if (is("<"))
    return true;
  if (!is("<<"))
    return false;
  for (std::size_t look = 1; look < 64; ++look) {
    const auto &token = peek(look);
    if (token.text == "implements")
      break;
    if (token.kind == TokenKind::End || token.kind == TokenKind::Newline ||
        token.text == ";" || token.text == "{" || token.text == "}")
      return false;
  }
  if (speculating)
    tokenEdits.push_back({position, tokens[position], true});
  auto first = tokens[position];
  first.text = "<";
  first.span.end = first.span.begin + 1;
  tokens[position].text = "<";
  ++tokens[position].span.begin;
  tokens.insert(tokens.begin() + static_cast<std::ptrdiff_t>(position), first);
  return true;
}
void Parser::undoTokenEdits(std::size_t keep) {
  while (tokenEdits.size() > keep) {
    auto &edit = tokenEdits.back();
    if (edit.inserted)
      tokens.erase(tokens.begin() + static_cast<std::ptrdiff_t>(edit.index));
    tokens[edit.index] = std::move(edit.before);
    tokenEdits.pop_back();
  }
}
// What may follow a generic application (language-grammar section 13.3). A
// newline is a follower only where it is not suppressed by an open bracket,
// which `peek` already guarantees.
bool Parser::followsGenericApplication() {
  const auto &next = peek();
  return next.kind == TokenKind::Newline || next.kind == TokenKind::End ||
         next.kind == TokenKind::FormatHoleClose || next.text == "(" ||
         next.text == "." || next.text == ")" || next.text == "]" ||
         next.text == "}" || next.text == "," || next.text == ";";
}
// Decides whether the `<` at the current position starts a generic
// application: a nonempty generic argument list followed by a follower. The
// decision is syntactic and never consults symbols. On rejection the parser
// state, including split `>>` tokens, is restored and the `<` is a comparison.
bool Parser::genericApplication(std::vector<GenericArgument> &arguments) {
  const auto start = position;
  const auto key =
      std::make_tuple(start, tokens.size(), parens, genericExpressionLevel);
  if (rejectedApplications.contains(key))
    return false;
  const auto savedParens = parens, savedNesting = nesting,
             savedLevel = genericExpressionLevel;
  const auto savedFailure = failedAt;
  const auto savedRejected = rejectedNames;
  const auto savedText = textSpans.size();
  const auto savedEdits = tokenEdits.size();
  const auto savedSpeculating = speculating;
  const auto savedAsync = inAsyncBody;
  const auto savedPending = pendingAsync;
  speculating = true;
  bool applied = false;
  try {
    auto parsed = genericArguments();
    applied = !parsed.empty() && followsGenericApplication();
    if (applied)
      arguments = std::move(parsed);
  } catch (ParseFailure &) {
  }
  speculating = savedSpeculating;
  if (applied) {
    if (!speculating)
      tokenEdits.clear();
    return true;
  }
  undoTokenEdits(savedEdits);
  parens = savedParens;
  nesting = savedNesting;
  genericExpressionLevel = savedLevel;
  failedAt = savedFailure;
  rejectedNames = savedRejected;
  textSpans.resize(savedText);
  inAsyncBody = savedAsync;
  pendingAsync = savedPending;
  position = start;
  rejectedApplications.insert(key);
  return false;
}
std::vector<GenericParameter>
Parser::genericParameters(std::vector<std::string> *regions) {
  std::vector<GenericParameter> result;
  if (!take("<"))
    return result;
  ++parens;
  do {
    if (is(">") || is(">>"))
      break;
    GenericParameter parameter;
    parameter.span = peek().span;
    if (take("region"))
      parameter.kind = GenericParameterKind::Region;
    else if (take("const"))
      parameter.kind = GenericParameterKind::Const;
    auto identifier = name();
    parameter.name = identifier.text;
    parameter.context = identifier.context;
    parameter.nameSpan = identifier.span;
    if (parameter.kind == GenericParameterKind::Region && regions)
      regions->push_back(parameter.name);
    if (take(":")) {
      if (parameter.kind == GenericParameterKind::Const)
        parameter.annotation = type(false);
      else {
        do {
          TypeSyntax bound;
          if (parameter.kind == GenericParameterKind::Region && take("static"))
            bound.name = "static";
          else if (take("?")) {
            auto identifier = name();
            bound.name = "?" + identifier.text;
            bound.context = identifier.context;
          } else
            bound = type(false);
          parameter.bounds.push_back(std::move(bound));
        } while (take("+"));
      }
    } else if (parameter.kind == GenericParameterKind::Const)
      fail("const parameter requires a declared scalar type");
    if (take("=")) {
      if (parameter.kind == GenericParameterKind::Const)
        parameter.defaultValue = genericValue();
      else if (parameter.kind == GenericParameterKind::Type)
        parameter.defaultType = type(false);
      else
        fail("region parameters cannot have defaults");
    }
    parameter.span.end = tokens[position - 1].span.end;
    result.push_back(std::move(parameter));
    if (result.size() > limits::locals)
      fail("generic parameter limit exceeded", "limit");
  } while (take(","));
  if (!genericClose())
    fail("expected '>' after generic parameters");
  --parens;
  return result;
}
std::vector<GenericArgument> Parser::genericArguments() {
  if (!genericOpen())
    fail("expected '<'");
  ++position;
  ++parens;
  std::vector<GenericArgument> result;
  do {
    if (is(">") || is(">>"))
      break;
    GenericArgument argument;
    argument.span = peek().span;
    auto explicitType = take("type");
    auto explicitConst = !explicitType && take("const");
    if (explicitType || (explicitConst && !is("{")) ||
        ((peek().kind == TokenKind::Word ||
          peek().kind == TokenKind::QuotedWord) &&
         peek(1).text == "=")) {
      argument.binding = name().text;
      expect("=");
    }
    auto payload = position;
    if (take("region")) {
      auto token = peek();
      argument.region = {take("static") ? "static" : name().text, token.span,
                         token.context};
    } else if (explicitConst ||
               (!explicitType &&
                (peek().kind == TokenKind::Integer ||
                 peek().kind == TokenKind::Character ||
                 peek().kind == TokenKind::Byte || is("-") || is("!") ||
                 is("true") || is("false") || is("{")))) {
      argument.value = genericValue();
    } else {
      argument.type = std::make_shared<const TypeSyntax>(type(false));
      if (!explicitType && !is(">>") && !is(">>=") &&
          binaryPrecedence(peek().text) >= 6) {
        position = payload;
        argument.type.reset();
        argument.value = genericValue();
      }
    }
    argument.span.end = tokens[position - 1].span.end;
    result.push_back(std::move(argument));
    if (result.size() > limits::locals)
      fail("generic argument limit exceeded", "limit");
  } while (take(","));
  if (!genericClose())
    fail("expected '>' after generic arguments");
  --parens;
  return result;
}
std::vector<GenericConstraint> Parser::genericConstraints() {
  std::vector<GenericConstraint> result;
  if (!takeContinuation("where"))
    return result;
  do {
    GenericConstraint constraint;
    constraint.span = peek().span;
    auto region = take("region");
    constraint.region = region;
    if (region && take("static"))
      constraint.subject.name = "static";
    else
      constraint.subject = type(false);
    if (take("="))
      constraint.equality = type(false);
    else {
      expect(":");
      do {
        TypeSyntax bound;
        if (take("static"))
          bound.name = "static";
        else if (take("?"))
          bound.name = "?" + name().text;
        else
          bound = type(false);
        constraint.bounds.push_back(std::move(bound));
      } while (take("+"));
    }
    constraint.span.end = tokens[position - 1].span.end;
    result.push_back(std::move(constraint));
  } while (take(","));
  return result;
}
} // namespace mettle::parsing
