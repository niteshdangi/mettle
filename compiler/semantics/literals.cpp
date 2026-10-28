#include "semantics/checker.h"
#include "support/limits.h"
#include <bit>
#include <charconv>
#include <regex>

namespace mettle {

Type Checker::annotation(const TypeSyntax &syntax, Span span,
                         std::string_view owner) {
  const auto &name = syntax.name;
  if (syntax.empty())
    return Type::Unknown;
  if (syntax.nested) {
    auto payload = annotation(*syntax.nested, span, owner);
    return syntax.view.empty()
               ? payload
               : checked.types->viewType(payload, syntax.view == "read"
                                                      ? ParameterMode::Read
                                                      : ParameterMode::Mut);
  }
  auto resolved = name == "Self" && !owner.empty() ? std::string(owner) : name;
  if (auto type = typeNames.find(resolved); type != typeNames.end()) {
    if (!syntax.view.empty())
      return checked.types->viewType(type->second, syntax.view == "read"
                                                       ? ParameterMode::Read
                                                       : ParameterMode::Mut);
    return type->second;
  }
  static const std::regex unsupported("([iu](8|16|32|64|128|size)|f(32|64))");
  error(std::regex_match(name, unsupported) ? "feature" : "name", span,
        "type '" + name + "' is not available in the I02 scalar subset");
  return Type::Unknown;
}
void Checker::literal(Node &n, bool negative) {
  static const std::regex pattern("([0-9]+(?:_[0-9]+)*)(i32)?");
  std::smatch match;
  if (!std::regex_match(n.text, match, pattern)) {
    static const std::regex other(
        "([0-9]+(?:_[0-9]+)*)([iu](8|16|32|64|128|size))");
    bool unsupported = std::regex_match(n.text, other) ||
                       n.text.starts_with("0x") || n.text.starts_with("0o") ||
                       n.text.starts_with("0b");
    error(unsupported ? "feature" : "lex", n.span,
          unsupported ? "only decimal i32 literals are implemented in I02"
                      : "malformed integer literal");
    facts(n).number = 0;
    return;
  }
  auto digits = match[1].str();
  digits.erase(std::remove(digits.begin(), digits.end(), '_'), digits.end());
  std::uint64_t magnitude = 0;
  auto parsed =
      std::from_chars(digits.data(), digits.data() + digits.size(), magnitude);
  if (parsed.ec != std::errc{} ||
      magnitude > (negative ? 2147483648ULL : 2147483647ULL)) {
    error("type", n.span, "integer literal is outside the i32 range");
    return;
  }
  auto bits = static_cast<std::uint32_t>(magnitude);
  if (negative)
    bits = 0u - bits;
  facts(n).number = std::bit_cast<std::int32_t>(bits);
}
} // namespace mettle
