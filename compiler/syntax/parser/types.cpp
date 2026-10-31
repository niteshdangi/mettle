#include "syntax/parser/detail.h"
#include <charconv>

namespace mettle::parsing {
TypeSyntax Parser::type(bool effect) {
  StateGuard guard(*this);
  if (++nesting > limits::parserNesting)
    fail("type nesting limit exceeded", "limit");
  TypeSyntax result;
  std::string view;
  if (is("read") || (is("mut") && peek(1).text != "fn"))
    view = tokens[position++].text;
  if (is("take") && peek(1).text != "fn")
    feature("'take' is an access mode, not a type qualifier");
  if (is("(") && peek(1).text == ")")
    fail("use Unit in type positions; () is a value");
  std::vector<std::string> binders;
  if (is("for")) {
    auto saved = position;
    expect("for");
    auto parameters = genericParameters();
    bool callable = is("fn") || is("mut") || is("take") || is("unsafe") ||
                    is("extern") || is("async");
    if (callable)
      position = saved;
    else {
      for (const auto &parameter : parameters) {
        if (parameter.kind != GenericParameterKind::Region)
          fail("higher-ranked binders may contain only regions");
        binders.push_back(parameter.name);
      }
    }
  }
  if (is("fn") || is("for") || is("unsafe") || is("extern") || is("async") ||
      ((is("mut") || is("take")) && peek(1).text == "fn"))
    result = callableType();
  else if (is("heap") || is("shared") || is("weak") || is("local")) {
    auto owner = tokens[position++];
    result.form = TypeForm::Owner;
    if (owner.text == "heap")
      result.ownerKind = OwnerKind::Heap;
    else if (owner.text == "shared")
      result.ownerKind = OwnerKind::Shared;
    else {
      if (owner.text == "local") {
        if (take("shared"))
          result.ownerKind = OwnerKind::LocalShared;
        else if (take("weak"))
          result.ownerKind = OwnerKind::LocalWeak;
        else
          fail("expected 'shared' or 'weak' after 'local'");
      } else
        result.ownerKind = OwnerKind::Weak;
    }
    auto payload = std::make_shared<const TypeSyntax>(type(false));
    result.nested = payload;
  } else if (take("pinned")) {
    result.form = TypeForm::Pinned;
    result.elements.push_back(type(false));
  } else if (take("ptr")) {
    result.form = TypeForm::Pointer;
    expect("<");
    if (!is("read") && !is("mut"))
      fail("raw pointers require read or mut access");
    result.name = tokens[position++].text;
    result.elements.push_back(type(false));
    if (!genericClose())
      fail("expected '>' after a raw pointer type");
  } else if (take("any") || take("some")) {
    result.form = tokens[position - 1].text == "any" ? TypeForm::Erased
                                                     : TypeForm::Opaque;
    do {
      result.elements.push_back(boundType());
    } while (take("+"));
  } else if (take("_")) {
    result.name = "_";
  } else if (take("(")) {
    ++parens;
    auto first = type();
    if (take(",")) {
      result.form = TypeForm::Tuple;
      result.elements.push_back(std::move(first));
      while (!is(")")) {
        result.elements.push_back(type());
        if (!take(","))
          break;
      }
    } else
      result = std::move(first);
    expect(")");
    --parens;
  } else if (take("[")) {
    ++parens;
    result.form = TypeForm::Array;
    result.elements.push_back(type());
    if (take(";"))
      result.countExpression = std::shared_ptr<const Node>(expr());
    else
      result.form = TypeForm::Slice;
    expect("]");
    --parens;
  } else {
    if (is("fn"))
      feature("callable types require callable typing");
    auto components = path();
    for (const auto &component : components) {
      if (!result.name.empty())
        result.name += "::";
      result.name += component;
    }
    if (genericOpen()) {
      result.arguments = genericArguments();
      for (const auto &argument : result.arguments)
        if (!argument.region.empty())
          result.regions.push_back(argument.region);
    }
  }
  result.binders = std::move(binders);
  while (is(".") && peek(1).text == "(") {
    TypeSyntax projection;
    projection.form = TypeForm::Projection;
    projection.elements.push_back(std::move(result));
    ++position;
    expect("(");
    ++parens;
    projection.elements.push_back(type(false));
    expect(")");
    --parens;
    expect(".");
    projection.name = name().text;
    if (genericOpen())
      projection.arguments = genericArguments();
    result = std::move(projection);
  }
  while (is("?") || is("??")) {
    auto depth = take("??") ? 2 : 1;
    if (depth == 1)
      expect("?");
    for (int i = 0; i < depth; ++i) {
      TypeSyntax optional;
      optional.form = TypeForm::Optional;
      optional.nested = std::make_shared<const TypeSyntax>(std::move(result));
      result = std::move(optional);
    }
  }
  if (!view.empty()) {
    TypeSyntax borrowed;
    borrowed.view = std::move(view);
    borrowed.nested = std::make_shared<const TypeSyntax>(std::move(result));
    result = std::move(borrowed);
  }
  if (take("from")) {
    bool grouped = take("(");
    do {
      result.sources.push_back(take("static") ? "static" : name().text);
    } while (grouped && take(","));
    if (grouped)
      expect(")");
  }
  if (effect && take("throws")) {
    TypeSyntax outcome;
    outcome.form = TypeForm::Outcome;
    outcome.elements.push_back(std::move(result));
    outcome.elements.push_back(type());
    result = std::move(outcome);
  }
  --nesting;
  return result;
}
} // namespace mettle::parsing
