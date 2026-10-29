#include "semantics/checker.h"
#include <limits>

namespace mettle {
std::optional<std::int32_t> Checker::constantInteger(const Node &node) {
  auto identity = constantType(node, Type::I32);
  if (identity == Type::Unknown)
    return std::nullopt;
  auto value = checked.types->constantValue(identity);
  if (!value || !isInteger(checked.types->parameter(identity).valueType) ||
      *value < std::numeric_limits<std::int32_t>::min() ||
      *value > std::numeric_limits<std::int32_t>::max()) {
    error("type", node.span,
          "required integer constant is outside the i32 range");
    return std::nullopt;
  }
  return static_cast<std::int32_t>(*value);
}
} // namespace mettle
