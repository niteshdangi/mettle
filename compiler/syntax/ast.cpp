#include "syntax/ast.h"

namespace mettle {
std::optional<bool> booleanLiteral(const Node &node) {
  const auto *value = &node;
  while (value->kind == Kind::Group)
    value = value->children[0].get();
  if (value->kind == Kind::Boolean)
    return value->text == "true";
  return std::nullopt;
}
bool isStatement(Kind kind) {
  return kind == Kind::Binding || kind == Kind::Assign ||
         kind == Kind::Return || kind == Kind::Break || kind == Kind::Continue;
}
} // namespace mettle
