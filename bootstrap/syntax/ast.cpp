#include "syntax/ast.h"
#include <algorithm>

namespace mettle {
std::optional<bool> booleanLiteral(const Node &node) {
  if (node.kind == Kind::Condition && node.patterns.empty())
    return booleanLiteral(*node.children[0]);
  if (node.kind == Kind::ConditionChain) {
    bool allTrue = true;
    for (const auto &condition : node.children) {
      auto value = booleanLiteral(*condition);
      if (value == false)
        return false;
      allTrue &= value == true;
    }
    return allTrue ? std::optional<bool>{true} : std::nullopt;
  }
  const auto *value = &node;
  while (value->kind == Kind::Group)
    value = value->children[0].get();
  if (value->kind == Kind::Boolean)
    return value->text == "true";
  return std::nullopt;
}
std::optional<std::string> dottedPath(const Node &node) {
  if (!node.genericArguments.empty() || !node.ownerGenericArguments.empty())
    return std::nullopt;
  if (node.kind == Kind::Name && node.annotation.form == TypeForm::Named)
    return node.text;
  if (node.kind != Kind::Field || node.flag || node.children.size() != 1)
    return std::nullopt;
  auto owner = dottedPath(*node.children[0]);
  if (!owner)
    return std::nullopt;
  return *owner + "::" + node.text;
}
std::unique_ptr<Node> formatRecipe(Span span,
                                   std::vector<std::unique_ptr<Node>> holes,
                                   std::vector<std::unique_ptr<Node>> pieces) {
  auto make = [](Kind kind, Span span, std::string text = "") {
    auto result = std::make_unique<Node>();
    result->kind = kind;
    result->span = span;
    result->text = std::move(text);
    return result;
  };
  auto internal = [&](std::string callee, Span span) {
    auto call = make(Kind::Call, span);
    call->label = std::string(formatInternalLabel);
    call->children.push_back(make(Kind::Name, span, std::move(callee)));
    return call;
  };
  auto grow = [](Node &value) {
    for (const auto &child : value.children) {
      value.depth = std::max(value.depth, child->depth + 1);
      value.span.end = std::max(value.span.end, child->span.end);
    }
  };
  std::unique_ptr<Node> result;
  if (holes.empty()) {
    result = internal("core::fmt::literal", span);
    result->children.push_back(std::move(pieces.back()));
  } else {
    result = internal("core::fmt::message", span);
    auto array = make(Kind::Array, span);
    for (std::size_t i = 0; i < holes.size(); ++i) {
      auto field = internal("core::fmt::field", holes[i]->span);
      field->children.push_back(std::move(holes[i]));
      field->children.push_back(std::move(pieces[i]));
      grow(*field);
      array->children.push_back(std::move(field));
    }
    grow(*array);
    auto view = make(Kind::Unary, span, "read");
    view->children.push_back(std::move(array));
    grow(*view);
    result->children.push_back(std::move(view));
    result->children.push_back(std::move(pieces.back()));
  }
  result->label = std::string(formatRecipeLabel);
  grow(*result);
  return result;
}
bool isStatement(Kind kind) {
  return kind == Kind::Binding || kind == Kind::Assign ||
         kind == Kind::Return || kind == Kind::Break || kind == Kind::Continue;
}
} // namespace mettle
