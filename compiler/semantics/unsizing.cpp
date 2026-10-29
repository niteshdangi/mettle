#include "semantics/checker.h"

namespace mettle {
bool Checker::unsizeCoercion(Node &expression, Type source, Type target,
                             Span span) {
  (void)span;
  auto actual = source, expected = target;
  if (checked.types->isView(target)) {
    if (!checked.types->isView(source))
      return false;
    const auto &from = checked.types->view(source);
    const auto &to = checked.types->view(target);
    if (to.mode == ParameterMode::Mut && from.mode != ParameterMode::Mut)
      return false;
    actual = from.payload;
    expected = to.payload;
  } else if (checked.types->isView(actual))
    actual = checked.types->view(actual).payload;
  auto sized = checked.types->unsizedArray(actual, expected);
  if (!sized)
    return false;
  const auto &array = checked.types->product(*sized);
  auto count = array.arrayCount == Type::Unknown
                   ? checked.types->constant(Type::I32, array.fields.size())
                   : array.arrayCount;
  facts(expression).unsizedSource = source;
  facts(expression).unsizedCount = count;
  facts(expression).rebuiltType = target;
  facts(expression).readView =
      checked.types->viewType(target, ParameterMode::Read);
  facts(expression).mutView =
      checked.types->viewType(target, ParameterMode::Mut);
  return true;
}
} // namespace mettle
