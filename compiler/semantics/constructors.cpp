#include "semantics/checker.h"

namespace mettle {
void Checker::constructor(Function &function) {
  if (!function.constructor)
    return;
  if (scopes.back().contains("self")) {
    error("name", function.span,
          "a constructor parameter cannot shadow 'self'");
    return;
  }
  auto type = annotation(function.annotation, function.span, function.owner);
  facts(function).constructorSelfSlot =
      local("self", inference.fresh(type), true, function.span);
}
} // namespace mettle
