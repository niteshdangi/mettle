#include "semantics/checker.h"
#include <algorithm>
#include <bit>

namespace mettle {
Type Checker::literal(const Node &node, bool negative) {
  auto spelling = node.text;
  auto suffix = Type::Unknown;
  for (auto type : {Type::I128, Type::U128, Type::Isize, Type::Usize, Type::I64,
                    Type::U64, Type::I32, Type::U32, Type::I16, Type::U16,
                    Type::I8, Type::U8, Type::F32, Type::F64}) {
    auto name = mettle::typeName(type);
    if (isFloating(type) &&
        (spelling.starts_with("0x") || spelling.starts_with("0o") ||
         spelling.starts_with("0b")))
      continue;
    if (spelling.ends_with(name)) {
      spelling.resize(spelling.size() - name.size());
      suffix = type;
      break;
    }
  }
  auto digit = [](char value) { return value >= '0' && value <= '9'; };
  for (std::size_t i = 0; i < spelling.size(); ++i)
    if (spelling[i] == '_' &&
        (i == 0 || i + 1 == spelling.size() || !digit(spelling[i - 1]) ||
         !digit(spelling[i + 1]))) {
      bool based = spelling.starts_with("0x") || spelling.starts_with("0o") ||
                   spelling.starts_with("0b");
      if (!based) {
        error("lex", node.span, "numeric separators must occur between digits");
        return suffix;
      }
    }
  spelling.erase(std::remove(spelling.begin(), spelling.end(), '_'),
                 spelling.end());
  NumericLiteral value;
  value.negative = negative;
  if (node.kind == Kind::Floating) {
    if (suffix != Type::Unknown && !isFloating(suffix))
      error("lex", node.span, "floating literal requires a floating suffix");
    if (negative)
      spelling.insert(spelling.begin(), '-');
    value.floating = std::move(spelling);
    if (!validFloatingLiteral(value.floating))
      error("lex", node.span, "malformed floating literal");
  } else {
    unsigned radix = 10;
    std::size_t position = 0;
    if (spelling.starts_with("0x") || spelling.starts_with("0o") ||
        spelling.starts_with("0b")) {
      radix = spelling[1] == 'x' ? 16 : spelling[1] == 'o' ? 8 : 2;
      position = 2;
    }
    if (position == spelling.size())
      error("lex", node.span, "integer literal requires digits");
    std::array<std::uint32_t, 4> limbs{};
    for (; position < spelling.size(); ++position) {
      auto c = spelling[position];
      unsigned digitValue = c >= '0' && c <= '9'   ? c - '0'
                            : c >= 'a' && c <= 'f' ? c - 'a' + 10
                            : c >= 'A' && c <= 'F' ? c - 'A' + 10
                                                   : 255;
      if (digitValue >= radix) {
        error("lex", node.span, "malformed integer literal");
        return suffix;
      }
      std::uint64_t carry = digitValue;
      for (auto &limb : limbs) {
        auto product = std::uint64_t{limb} * radix + carry;
        limb = static_cast<std::uint32_t>(product);
        carry = product >> 32;
      }
      if (carry) {
        error("type", node.span, "integer literal exceeds 128 bits");
        return suffix;
      }
    }
    value.magnitude = {
        std::uint64_t{limbs[0]} | (std::uint64_t{limbs[1]} << 32),
        std::uint64_t{limbs[2]} | (std::uint64_t{limbs[3]} << 32)};
    if (value.magnitude == std::array<std::uint64_t, 2>{})
      value.negative = false;
    auto low = static_cast<std::uint32_t>(value.magnitude[0]);
    facts(node).number = std::bit_cast<std::int32_t>(negative ? 0u - low : low);
  }
  facts(node).numeric = std::move(value);
  return suffix;
}
} // namespace mettle
