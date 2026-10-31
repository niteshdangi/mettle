#include "semantics/checker.h"

namespace mettle {
bool Checker::ownerUnsizeCoercion(Node &expression, Type source,
                                  Type target, Span span) {
  if (!checked.types->isProduct(source) ||
      !checked.types->isProduct(target))
    return false;
  const auto &from = checked.types->product(source);
  const auto &to = checked.types->product(target);
  if (from.genericOrigin == Type::Unknown ||
      from.genericOrigin != to.genericOrigin ||
      checked.types->product(from.genericOrigin).name !=
          "alloc::boxed::Box" ||
      from.genericArguments.size() < 2 ||
      from.genericArguments.size() != to.genericArguments.size() ||
      from.fields.empty() || from.fields.size() != to.fields.size())
    return false;
  auto sourcePayload = from.genericArguments.front();
  auto targetPayload = to.genericArguments.front();
  if (sourcePayload == targetPayload ||
      !checked.types->isSized(sourcePayload) ||
      !checked.types->isPointer(from.fields.front().type) ||
      !checked.types->isPointer(to.fields.front().type))
    return false;
  const auto &sourcePointer =
      checked.types->pointer(from.fields.front().type);
  const auto &targetPointer = checked.types->pointer(to.fields.front().type);
  if (sourcePointer.mode != ParameterMode::Mut ||
      targetPointer.mode != ParameterMode::Mut ||
      sourcePointer.payload != sourcePayload ||
      targetPointer.payload != targetPayload)
    return false;
  for (std::size_t p = 1; p < from.genericArguments.size(); ++p)
    if (from.genericArguments[p] != to.genericArguments[p])
      return false;
  for (std::size_t p = 1; p < from.fields.size(); ++p)
    if (from.fields[p].type != to.fields[p].type)
      return false;

  bool unsizedArray =
      checked.types->unsizedArray(sourcePayload, targetPayload).has_value();
  auto erased = checked.types->erasedTail(sourcePayload, targetPayload);
  bool erasedPayload =
      erased && erased->first == sourcePayload &&
      erased->second == targetPayload && checked.types->isErased(targetPayload);
  if (!unsizedArray && !erasedPayload)
    return false;
  if (erasedPayload) {
    if (!interfaceObligation(sourcePayload, targetPayload, span))
      return true;
    erasedUses.emplace(targetPayload, span);
  }
  facts(expression).ownerUnsizeSource = source;
  facts(expression).rebuiltType = target;
  return true;
}

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
