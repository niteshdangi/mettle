#include "semantics/checker.h"

namespace mettle {
std::string Checker::definitionName(Span span,
                                    std::string_view spelling) const {
  auto canonical = checked.symbols->canonical(span);
  return canonical.empty() ? std::string(spelling) : canonical;
}

std::string Checker::typeName(std::string_view spelling, Span span,
                              std::string_view owner) const {
  if (spelling == "Self" && !owner.empty())
    spelling = owner;
  auto resolved =
      checked.symbols->lookup(checked.symbols->moduleOf(span), spelling,
                              resolution::Namespace::Type, span);
  if (resolved)
    return *resolved;
  if (builtinType(spelling) != Type::Unknown)
    return std::string(spelling);
  return {};
}

std::string Checker::callableName(std::string_view spelling,
                                  std::string_view owner, Span span) const {
  auto context = checked.symbols->moduleOf(span);
  if (auto resolved = checked.symbols->lookup(
          context, spelling, resolution::Namespace::Value, span))
    return *resolved;
  if (auto type = typeName(spelling, span, owner); !type.empty())
    return type;
  auto separator = spelling.rfind("::");
  if (separator == std::string_view::npos)
    return {};
  auto prefix = typeName(spelling.substr(0, separator), span, owner);
  auto found = typeNames.find(prefix);
  if (found == typeNames.end() || !checked.types->isProduct(found->second))
    return {};
  auto canonical = checked.types->product(found->second).name;
  auto member = spelling.substr(separator + 2);
  return checked.symbols
      ->lookup(context, "package::" + canonical + "::" + std::string(member),
               resolution::Namespace::Value, span)
      .value_or("");
}

bool Checker::visibleField(Type type, std::size_t field, Span use) {
  auto kind = checked.types->product(type).kind;
  if (kind == AggregateKind::Uninit || kind == AggregateKind::ManualDrop ||
      kind == AggregateKind::UnsafeCell || kind == AggregateKind::Pin ||
      kind == AggregateKind::Atomic || kind == AggregateKind::Cell ||
      kind == AggregateKind::RefCell || kind == AggregateKind::Ref ||
      kind == AggregateKind::RefMut || kind == AggregateKind::VarArgs) {
    error("name", use, "compiler-owned storage fields are private");
    return false;
  }
  if (checked.types->product(type).genericOrigin != Type::Unknown)
    type = checked.types->product(type).genericOrigin;
  const auto &name = checked.types->product(type).name;
  for (const auto &product : module.products) {
    if (definitionName(product.span, product.name) != name)
      continue;
    if (product.enumeration || field >= product.fields.size())
      return true;
    if (checked.symbols->accessible(product.fields[field].span,
                                    checked.symbols->moduleOf(use)))
      return true;
    error("name", use,
          "private or restricted field '" + product.fields[field].name +
              "' is inaccessible");
    return false;
  }
  return true;
}
} // namespace mettle
