#include "types/machine.h"
#include <algorithm>
#include <bit>
#include <stdexcept>

namespace mettle {
namespace {
using Magnitude = std::array<std::uint64_t, 2>;
bool zero(Magnitude a) { return a[0] == 0 && a[1] == 0; }
unsigned bitWidth(Magnitude value) {
  return value[1] ? 128u - static_cast<unsigned>(std::countl_zero(value[1]))
                  : 64u - static_cast<unsigned>(std::countl_zero(value[0]));
}
int compare(Magnitude a, Magnitude b) {
  if (a[1] != b[1])
    return a[1] < b[1] ? -1 : 1;
  return a[0] == b[0] ? 0 : a[0] < b[0] ? -1 : 1;
}
Magnitude subtract(Magnitude a, Magnitude b) {
  return {a[0] - b[0], a[1] - b[1] - (a[0] < b[0])};
}
Magnitude add(Magnitude a, Magnitude b, bool &overflow) {
  auto low = a[0] + b[0];
  auto high = a[1] + b[1];
  overflow = high < a[1];
  auto carry = low < a[0];
  overflow |= high + carry < high;
  return {low, high + carry};
}
Magnitude multiply(Magnitude a, Magnitude b, bool &overflow) {
  std::array<std::uint32_t, 8> product{};
  for (unsigned i = 0; i < 4; ++i) {
    std::uint64_t carry = 0;
    auto left = static_cast<std::uint32_t>(a[i / 2] >> (32 * (i % 2)));
    for (unsigned j = 0; j < 4; ++j) {
      auto right = static_cast<std::uint32_t>(b[j / 2] >> (32 * (j % 2)));
      auto digit = std::uint64_t{left} * right + product[i + j] + carry;
      product[i + j] = static_cast<std::uint32_t>(digit);
      carry = digit >> 32;
    }
    product[i + 4] = static_cast<std::uint32_t>(carry);
  }
  overflow = product[4] || product[5] || product[6] || product[7];
  return {std::uint64_t{product[0]} | (std::uint64_t{product[1]} << 32),
          std::uint64_t{product[2]} | (std::uint64_t{product[3]} << 32)};
}
Magnitude shiftLeft(Magnitude a) {
  return {a[0] << 1, (a[1] << 1) | (a[0] >> 63)};
}
Magnitude shiftRight(Magnitude a) {
  return {(a[0] >> 1) | (a[1] << 63), a[1] >> 1};
}
bool bit(Magnitude a, unsigned position) {
  return (a[position / 64] >> (position % 64)) & 1;
}
void setBit(Magnitude &a, unsigned position) {
  a[position / 64] |= std::uint64_t{1} << (position % 64);
}
std::pair<Magnitude, Magnitude> divide(Magnitude a, Magnitude b) {
  Magnitude quotient{}, remainder{};
  for (unsigned position = bitWidth(a); position-- > 0;) {
    bool carry = remainder[1] >> 63;
    remainder = shiftLeft(remainder);
    remainder[0] |= bit(a, position);
    if (carry || compare(remainder, b) >= 0) {
      remainder = subtract(remainder, b);
      setBit(quotient, position);
    }
  }
  return {quotient, remainder};
}
Magnitude mask(unsigned width) {
  if (width == 128)
    return {~std::uint64_t{0}, ~std::uint64_t{0}};
  if (width >= 64)
    return {~std::uint64_t{0}, (std::uint64_t{1} << (width - 64)) - 1};
  return {(std::uint64_t{1} << width) - 1, 0};
}
Magnitude encode(const NumericLiteral &value, unsigned width) {
  auto bits = value.negative ? subtract({}, value.magnitude) : value.magnitude;
  auto bound = mask(width);
  return {bits[0] & bound[0], bits[1] & bound[1]};
}
NumericLiteral decode(Magnitude bits, Type type) {
  auto width = integerWidth(type);
  auto bound = mask(width);
  bits = {bits[0] & bound[0], bits[1] & bound[1]};
  NumericLiteral result;
  result.negative = isSignedInteger(type) && bit(bits, width - 1);
  if (result.negative) {
    bits = subtract({}, bits);
    bits = {bits[0] & bound[0], bits[1] & bound[1]};
  }
  result.magnitude = bits;
  return result;
}
NumericLiteral boolean(bool value) {
  NumericLiteral result;
  result.magnitude[0] = value;
  return result;
}
NumericLiteral arithmetic(std::string_view op, const NumericLiteral &a,
                          const NumericLiteral &b, bool &overflow) {
  NumericLiteral result;
  overflow = false;
  if (op == "*") {
    result.negative = a.negative != b.negative;
    result.magnitude = multiply(a.magnitude, b.magnitude, overflow);
  } else {
    auto negative = b.negative != (op == "-");
    if (a.negative == negative) {
      result.negative = a.negative;
      result.magnitude = add(a.magnitude, b.magnitude, overflow);
    } else if (compare(a.magnitude, b.magnitude) >= 0) {
      result.negative = a.negative;
      result.magnitude = subtract(a.magnitude, b.magnitude);
    } else {
      result.negative = negative;
      result.magnitude = subtract(b.magnitude, a.magnitude);
    }
  }
  if (!overflow && zero(result.magnitude))
    result.negative = false;
  return result;
}
Type oppositeInteger(Type type) {
  if (type == Type::I8 || type == Type::U8)
    return type == Type::I8 ? Type::U8 : Type::I8;
  if (type == Type::I16 || type == Type::U16)
    return type == Type::I16 ? Type::U16 : Type::I16;
  if (type == Type::I32 || type == Type::U32)
    return type == Type::I32 ? Type::U32 : Type::I32;
  if (type == Type::I64 || type == Type::U64)
    return type == Type::I64 ? Type::U64 : Type::I64;
  if (type == Type::I128 || type == Type::U128)
    return type == Type::I128 ? Type::U128 : Type::I128;
  return type == Type::Isize ? Type::Usize : Type::Isize;
}
Magnitude squareRoot(Magnitude value) {
  Magnitude root{}, remainder{};
  for (unsigned pair = 64; pair-- > 0;) {
    remainder = shiftLeft(shiftLeft(remainder));
    remainder[0] |= unsigned(bit(value, 2 * pair)) |
                    (unsigned(bit(value, 2 * pair + 1)) << 1);
    root = shiftLeft(root);
    auto trial = shiftLeft(root);
    trial[0] |= 1;
    if (compare(remainder, trial) >= 0) {
      remainder = subtract(remainder, trial);
      root[0] |= 1;
    }
  }
  return root;
}
unsigned integerLog(Magnitude value, Magnitude base) {
  if (compare(value, base) < 0)
    return 0;
  // An unsigned 128-bit value admits at most seven powers base^(2^i).
  std::array<Magnitude, 7> powers{};
  unsigned count = 0;
  while (count < powers.size()) {
    powers[count++] = base;
    bool overflow = false;
    auto square = multiply(base, base, overflow);
    if (overflow || compare(square, value) > 0)
      break;
    base = square;
  }
  unsigned result = 0;
  while (count-- > 0)
    if (compare(value, powers[count]) >= 0) {
      value = divide(value, powers[count]).first;
      result |= 1u << count;
    }
  return result;
}
} // namespace
NumericLiteral integerLiteral(std::int64_t value) {
  NumericLiteral result;
  result.negative = value < 0;
  result.magnitude[0] = value < 0 ? 0 - static_cast<std::uint64_t>(value)
                                  : static_cast<std::uint64_t>(value);
  return result;
}
std::string integerLiteralName(const NumericLiteral &value) {
  auto magnitude = value.magnitude;
  std::string result;
  do {
    auto [quotient, remainder] = divide(magnitude, {10, 0});
    result.push_back(static_cast<char>('0' + remainder[0]));
    magnitude = quotient;
  } while (!zero(magnitude));
  if (value.negative && !zero(value.magnitude))
    result.push_back('-');
  std::reverse(result.begin(), result.end());
  return result;
}
int compareIntegers(const NumericLiteral &left, const NumericLiteral &right) {
  if (left.negative != right.negative)
    return left.negative ? -1 : 1;
  auto order = compare(left.magnitude, right.magnitude);
  return left.negative ? -order : order;
}
NumericLiteral integerMinimum(Type type) {
  NumericLiteral result;
  if (isSignedInteger(type)) {
    result.negative = true;
    setBit(result.magnitude, integerWidth(type) - 1);
  }
  return result;
}
NumericLiteral integerMaximum(Type type) {
  NumericLiteral result;
  result.magnitude = mask(integerWidth(type) - isSignedInteger(type));
  return result;
}
NumericLiteral integerMinimum(Type type, unsigned pointerBits) {
  return integerMinimum(integerEquivalent(type, pointerBits));
}
NumericLiteral integerMaximum(Type type, unsigned pointerBits) {
  return integerMaximum(integerEquivalent(type, pointerBits));
}
NumericLiteral evaluateIntegerConstant(std::string_view op, Type type,
                                       const NumericLiteral &a,
                                       const NumericLiteral &b,
                                       unsigned pointerBits) {
  return evaluateIntegerConstant(op, integerEquivalent(type, pointerBits), a,
                                 b);
}
NumericLiteral evaluateIntegerConstant(std::string_view op, Type type,
                                       const NumericLiteral &a,
                                       const NumericLiteral &b) {
  auto order = compareIntegers(a, b);
  if (op == "==")
    return boolean(order == 0);
  if (op == "!=")
    return boolean(order != 0);
  if (op == "<")
    return boolean(order < 0);
  if (op == "<=")
    return boolean(order <= 0);
  if (op == ">")
    return boolean(order > 0);
  if (op == ">=")
    return boolean(order >= 0);
  if (op == "&&" || op == "||")
    return boolean(op == "&&" ? !zero(a.magnitude) && !zero(b.magnitude)
                              : !zero(a.magnitude) || !zero(b.magnitude));
  NumericLiteral result;
  bool overflow = false;
  if (op == "+" || op == "-" || op == "*")
    result = arithmetic(op, a, b, overflow);
  else if (op == "/" || op == "%") {
    if (zero(b.magnitude))
      throw std::invalid_argument("division by zero in constant expression");
    if (isSignedInteger(type) && a == integerMinimum(type) &&
        b == integerLiteral(-1))
      overflow = true;
    auto [quotient, remainder] = divide(a.magnitude, b.magnitude);
    result.magnitude = op == "/" ? quotient : remainder;
    result.negative = op == "/" ? a.negative != b.negative : a.negative;
  } else if (op == "&" || op == "|" || op == "^") {
    auto left = encode(a, integerWidth(type)),
         right = encode(b, integerWidth(type));
    Magnitude bits{};
    for (unsigned i = 0; i < 2; ++i)
      bits[i] = op == "&"   ? left[i] & right[i]
                : op == "|" ? left[i] | right[i]
                            : left[i] ^ right[i];
    return decode(bits, type);
  } else if (op == "<<" || op == ">>") {
    auto width = integerWidth(type);
    if (b.negative || b.magnitude[1] || b.magnitude[0] >= width)
      throw std::invalid_argument("invalid shift in constant expression");
    auto bits = encode(a, width);
    for (std::uint64_t i = 0; i < b.magnitude[0]; ++i) {
      if (op == "<<")
        bits = shiftLeft(bits);
      else {
        bits = shiftRight(bits);
        if (a.negative)
          setBit(bits, width - 1);
      }
    }
    return decode(bits, type);
  } else
    throw std::invalid_argument(
        "unsupported operator in required integer constant");
  if (zero(result.magnitude))
    result.negative = false;
  if (overflow || !integerLiteralFits(result, type))
    throw std::invalid_argument("required integer constant overflows");
  return result;
}

std::optional<IntegerMethodResult>
evaluateIntegerMethod(std::string_view method, Type owner,
                      std::span<const NumericLiteral> operands,
                      unsigned pointerBits, bool littleEndian) {
  if (!isInteger(owner))
    throw std::invalid_argument("integer method requires an integer owner");
  if ((owner == Type::Isize || owner == Type::Usize) && pointerBits != 16 &&
      pointerBits != 32 && pointerBits != 64)
    throw std::invalid_argument("invalid target integer pointer width");
  auto type = integerEquivalent(owner, pointerBits);
  auto width = integerWidth(type);
  auto sign = isSignedInteger(type);
  auto unsignedOwner = sign ? oppositeInteger(owner) : owner;
  auto signedOwner = sign ? owner : oppositeInteger(owner);
  auto require = [&](std::size_t count) {
    if (operands.size() != count)
      throw std::invalid_argument("invalid integer method operand count");
  };
  auto input = [&](std::size_t index, Type expected) {
    if (index >= operands.size() ||
        !integerLiteralFits(operands[index], expected, pointerBits))
      throw std::invalid_argument("invalid integer method operand");
    auto value = operands[index];
    if (zero(value.magnitude))
      value.negative = false;
    return value;
  };
  auto result = [](Type resultType, NumericLiteral value, bool failed = false) {
    return IntegerMethodResult{resultType, std::move(value), failed};
  };
  auto predicate = [&](bool value) {
    return result(Type::Bool, boolean(value));
  };
  auto bitsResult = [&](Magnitude bits, Type resultType) {
    return result(resultType,
                  decode(bits, integerEquivalent(resultType, pointerBits)));
  };
  auto countResult = [&](unsigned value, bool failed = false) {
    return result(Type::U32, integerLiteral(value), failed);
  };
  auto unary = [&] {
    require(1);
    return input(0, owner);
  };
  auto binary = [&](Type right) {
    require(2);
    return std::pair{input(0, owner), input(1, right)};
  };

  if (method == "count_ones" || method == "count_zeros" ||
      method == "leading_zeros" || method == "leading_ones" ||
      method == "trailing_zeros" || method == "trailing_ones" ||
      method == "bit_width" || method == "highest_one" ||
      method == "lowest_one" || method == "isolate_highest_one" ||
      method == "isolate_lowest_one" || method == "reverse_bits" ||
      method == "swap_bytes" || method == "to_be" || method == "from_be" ||
      method == "to_le" || method == "from_le") {
    if (method == "bit_width" && sign)
      throw std::invalid_argument("bit_width requires an unsigned integer");
    auto value = encode(unary(), width);
    if (method == "count_ones" || method == "count_zeros") {
      auto ones = static_cast<unsigned>(std::popcount(value[0]) +
                                        std::popcount(value[1]));
      return countResult(method == "count_ones" ? ones : width - ones);
    }
    if (method == "bit_width")
      return countResult(bitWidth(value));
    bool lowest = method == "lowest_one" || method == "isolate_lowest_one";
    if (method == "highest_one" || method == "lowest_one" ||
        method == "isolate_highest_one" || method == "isolate_lowest_one") {
      unsigned index = 0;
      if (!zero(value)) {
        if (lowest)
          index = value[0]
                      ? static_cast<unsigned>(std::countr_zero(value[0]))
                      : 64u + static_cast<unsigned>(std::countr_zero(value[1]));
        else
          index = bitWidth(value) - 1;
      }
      if (method == "highest_one" || method == "lowest_one")
        return countResult(index, zero(value));
      Magnitude isolated{};
      if (!zero(value))
        setBit(isolated, index);
      return bitsResult(isolated, owner);
    }
    if (method.starts_with("leading_") || method.starts_with("trailing_")) {
      unsigned count = 0;
      bool ones = method.ends_with("_ones");
      bool leading = method.starts_with("leading_");
      while (count < width &&
             bit(value, leading ? width - count - 1 : count) == ones)
        ++count;
      return countResult(count);
    }
    bool endian = method == "to_be" || method == "from_be" ||
                  method == "to_le" || method == "from_le";
    if (endian && (method.ends_with("_le") == littleEndian))
      return bitsResult(value, owner);
    Magnitude reversed{};
    for (unsigned position = 0; position < width; ++position)
      if (bit(value, position)) {
        auto target = method == "reverse_bits"
                          ? width - position - 1
                          : width - 8 - (position / 8) * 8 + position % 8;
        setBit(reversed, target);
      }
    return bitsResult(reversed, owner);
  }
  if (method == "rotate_left" || method == "rotate_right") {
    auto [a, b] = binary(Type::U32);
    auto count = static_cast<unsigned>(b.magnitude[0] % width);
    auto value = encode(a, width);
    Magnitude rotated{};
    for (unsigned position = 0; position < width; ++position)
      if (bit(value, position))
        setBit(rotated, method == "rotate_left"
                            ? (position + count) % width
                            : (position + width - count) % width);
    return bitsResult(rotated, owner);
  }
  if (method == "cast_signed" || method == "cast_unsigned") {
    if ((method == "cast_signed") == sign)
      throw std::invalid_argument("invalid integer signedness cast");
    return bitsResult(encode(unary(), width), oppositeInteger(owner));
  }
  if (method == "unsigned_abs") {
    if (!sign)
      throw std::invalid_argument("unsigned_abs requires a signed integer");
    auto value = unary();
    value.negative = false;
    return result(unsignedOwner, value);
  }
  if (method == "abs_diff" || method == "checked_signed_diff") {
    if (method == "checked_signed_diff" && sign)
      throw std::invalid_argument("signed difference requires unsigned inputs");
    auto [a, b] = binary(owner);
    bool overflow = false;
    auto difference = arithmetic("-", a, b, overflow);
    if (method == "checked_signed_diff") {
      bool failed =
          overflow || !integerLiteralFits(difference, signedOwner, pointerBits);
      return result(signedOwner,
                    decode(encode(difference, width),
                           integerEquivalent(signedOwner, pointerBits)),
                    failed);
    }
    difference.negative = false;
    return result(unsignedOwner, difference);
  }
  if (method == "is_positive" || method == "is_negative" ||
      method == "signum") {
    if (!sign)
      throw std::invalid_argument("sign query requires a signed integer");
    auto value = unary();
    if (method == "is_negative")
      return predicate(value.negative);
    if (method == "is_positive")
      return predicate(!value.negative && !zero(value.magnitude));
    return result(owner, integerLiteral(zero(value.magnitude) ? 0
                                        : value.negative      ? -1
                                                              : 1));
  }
  if (method == "is_power_of_two" || method == "next_power_of_two" ||
      method == "checked_next_power_of_two") {
    if (sign)
      throw std::invalid_argument("power of two requires an unsigned integer");
    auto value = unary().magnitude;
    if (method == "is_power_of_two")
      return predicate(std::popcount(value[0]) + std::popcount(value[1]) == 1);
    auto exponent = zero(value) ? 0u : bitWidth(subtract(value, {1, 0}));
    bool overflow = exponent >= width;
    if (overflow && method == "next_power_of_two")
      throw std::invalid_argument("required integer constant overflows");
    Magnitude power{};
    if (!overflow)
      setBit(power, exponent);
    return result(owner, decode(power, type), overflow);
  }
  if (method == "div_ceil" || method == "next_multiple_of" ||
      method == "checked_next_multiple_of" || method == "is_multiple_of") {
    if (sign)
      throw std::invalid_argument(
          "multiple operation requires unsigned inputs");
    auto [a, b] = binary(owner);
    bool optional = method == "checked_next_multiple_of";
    if (zero(b.magnitude)) {
      if (method == "is_multiple_of")
        return predicate(zero(a.magnitude));
      if (optional)
        return result(owner, {}, true);
      throw std::invalid_argument("division by zero in constant expression");
    }
    auto [quotient, remainder] = divide(a.magnitude, b.magnitude);
    if (method == "is_multiple_of")
      return predicate(zero(remainder));
    bool overflow = false;
    auto rounded = method == "div_ceil"
                       ? add(quotient, {zero(remainder) ? 0u : 1u, 0}, overflow)
                       : add(a.magnitude,
                             zero(remainder) ? Magnitude{}
                                             : subtract(b.magnitude, remainder),
                             overflow);
    NumericLiteral value;
    value.magnitude = rounded;
    overflow |= !integerLiteralFits(value, type);
    if (overflow && !optional)
      throw std::invalid_argument("required integer constant overflows");
    return result(owner, decode(rounded, type), overflow);
  }
  if (method == "midpoint") {
    auto [a, b] = binary(owner);
    bool overflow = false;
    auto sum = arithmetic("+", a, b, overflow);
    sum.magnitude = shiftRight(sum.magnitude);
    if (overflow)
      setBit(sum.magnitude, 127);
    if (zero(sum.magnitude))
      sum.negative = false;
    return result(owner, sum);
  }
  if (method == "isqrt" || method == "checked_isqrt") {
    auto value = unary();
    if (value.negative) {
      if (method == "checked_isqrt")
        return result(owner, {}, true);
      throw std::invalid_argument(
          "negative square root in constant expression");
    }
    value.magnitude = squareRoot(value.magnitude);
    return result(owner, value);
  }
  if (method == "ilog" || method == "checked_ilog" || method == "ilog2" ||
      method == "checked_ilog2" || method == "ilog10" ||
      method == "checked_ilog10") {
    bool baseArgument = method == "ilog" || method == "checked_ilog";
    NumericLiteral value, base;
    if (baseArgument) {
      auto inputs = binary(owner);
      value = inputs.first;
      base = inputs.second;
    } else {
      value = unary();
      base = integerLiteral(method.ends_with("ilog2") ? 2 : 10);
    }
    bool invalid = value.negative || zero(value.magnitude) || base.negative ||
                   compare(base.magnitude, {2, 0}) < 0;
    if (invalid) {
      if (method.starts_with("checked_"))
        return countResult(0, true);
      throw std::invalid_argument(
          "invalid integer logarithm in constant expression");
    }
    return countResult(method.ends_with("ilog2")
                           ? bitWidth(value.magnitude) - 1
                           : integerLog(value.magnitude, base.magnitude));
  }
  if (method == "is_ascii" || method == "is_ascii_alphabetic" ||
      method == "is_ascii_alphanumeric" || method == "is_ascii_control" ||
      method == "is_ascii_digit" || method == "is_ascii_graphic" ||
      method == "is_ascii_hexdigit" || method == "is_ascii_lowercase" ||
      method == "is_ascii_punctuation" || method == "is_ascii_uppercase" ||
      method == "is_ascii_whitespace" || method == "to_ascii_lowercase" ||
      method == "to_ascii_uppercase" || method == "eq_ignore_ascii_case") {
    if (owner != Type::U8)
      throw std::invalid_argument("ASCII method requires u8");
    auto lower = [](std::uint64_t value) {
      return value >= 'A' && value <= 'Z' ? value + 32 : value;
    };
    if (method == "eq_ignore_ascii_case") {
      auto [a, b] = binary(owner);
      return predicate(lower(a.magnitude[0]) == lower(b.magnitude[0]));
    }
    auto value = unary().magnitude[0];
    bool upper = value >= 'A' && value <= 'Z';
    bool lowercase = value >= 'a' && value <= 'z';
    bool digit = value >= '0' && value <= '9';
    bool graphic = value >= 0x21 && value <= 0x7e;
    if (method == "to_ascii_lowercase" || method == "to_ascii_uppercase") {
      auto converted = method == "to_ascii_lowercase" ? lower(value)
                       : lowercase                    ? value - 32
                                                      : value;
      return result(owner,
                    integerLiteral(static_cast<std::int64_t>(converted)));
    }
    if (method == "is_ascii")
      return predicate(value < 0x80);
    if (method == "is_ascii_alphabetic")
      return predicate(upper || lowercase);
    if (method == "is_ascii_alphanumeric")
      return predicate(upper || lowercase || digit);
    if (method == "is_ascii_control")
      return predicate(value < 0x20 || value == 0x7f);
    if (method == "is_ascii_digit")
      return predicate(digit);
    if (method == "is_ascii_graphic")
      return predicate(graphic);
    if (method == "is_ascii_hexdigit")
      return predicate(digit || (value >= 'A' && value <= 'F') ||
                       (value >= 'a' && value <= 'f'));
    if (method == "is_ascii_lowercase")
      return predicate(lowercase);
    if (method == "is_ascii_punctuation")
      return predicate(graphic && !upper && !lowercase && !digit);
    if (method == "is_ascii_uppercase")
      return predicate(upper);
    return predicate(value == 0x20 ||
                     (value >= 0x09 && value <= 0x0d && value != 0x0b));
  }
  if (method == "carrying_add" || method == "borrowing_sub") {
    if (sign)
      throw std::invalid_argument("carry operation requires unsigned inputs");
    require(3);
    auto a = input(0, owner), b = input(1, owner);
    auto carry = input(2, Type::Bool);
    bool firstOverflow = false, secondOverflow = false;
    auto op = method == "carrying_add" ? "+" : "-";
    auto first = arithmetic(op, a, b, firstOverflow);
    firstOverflow |= !integerLiteralFits(first, type);
    first = decode(encode(first, width), type);
    auto second = arithmetic(op, first, carry, secondOverflow);
    secondOverflow |= !integerLiteralFits(second, type);
    return result(owner, decode(encode(second, width), type),
                  firstOverflow || secondOverflow);
  }

  enum class Mode {
    Ordinary,
    Checked,
    Wrapping,
    Overflowing,
    Saturating,
    Strict,
    Unchecked,
    Unbounded
  };
  auto mode = Mode::Ordinary;
  if (method.starts_with("checked_")) {
    mode = Mode::Checked;
    method.remove_prefix(8);
  } else if (method.starts_with("wrapping_")) {
    mode = Mode::Wrapping;
    method.remove_prefix(9);
  } else if (method.starts_with("overflowing_")) {
    mode = Mode::Overflowing;
    method.remove_prefix(12);
  } else if (method.starts_with("saturating_")) {
    mode = Mode::Saturating;
    method.remove_prefix(11);
  } else if (method.starts_with("strict_")) {
    mode = Mode::Strict;
    method.remove_prefix(7);
  } else if (method.starts_with("unchecked_")) {
    mode = Mode::Unchecked;
    method.remove_prefix(10);
  } else if (method.starts_with("unbounded_")) {
    mode = Mode::Unbounded;
    method.remove_prefix(10);
  }
  bool mixedSigned = method.ends_with("_signed");
  bool mixedUnsigned = method.ends_with("_unsigned");
  if (mixedSigned || mixedUnsigned)
    method.remove_suffix(mixedSigned ? 7 : 9);
  bool mixed = mixedSigned || mixedUnsigned;
  bool shift = method == "shl" || method == "shr";
  bool unaryMethod = method == "neg" || method == "abs";
  bool division = method == "div" || method == "rem" ||
                  method == "div_euclid" || method == "rem_euclid";
  bool remainder = method == "rem" || method == "rem_euclid";
  bool basic = method == "add" || method == "sub" || method == "mul";
  bool power = method == "pow";
  if (!basic && !unaryMethod && !shift && !division && !power)
    return std::nullopt;
  if (mixed && (!basic || method == "mul" || mode == Mode::Unchecked ||
                mode == Mode::Unbounded))
    return std::nullopt;
  if ((mode == Mode::Unchecked && !(basic || method == "neg" || shift)) ||
      (mode == Mode::Unbounded && !shift) ||
      (mode == Mode::Saturating &&
       (shift || remainder || method == "div_euclid")) ||
      (mode == Mode::Ordinary && !mixed && method != "abs" && method != "pow" &&
       method != "div_euclid" && method != "rem_euclid"))
    return std::nullopt;
  if (mixed && ((mixedSigned && sign) || (mixedUnsigned && !sign)))
    throw std::invalid_argument("invalid mixed integer method signedness");
  if (method == "abs" && !sign)
    throw std::invalid_argument("abs requires a signed integer");
  NumericLiteral a, b;
  if (unaryMethod)
    a = unary();
  else {
    auto inputs = binary(shift || power ? Type::U32
                         : mixed        ? oppositeInteger(owner)
                                        : owner);
    a = inputs.first;
    b = inputs.second;
  }
  auto finish = [&](NumericLiteral value, bool overflow) {
    overflow |= !integerLiteralFits(value, type);
    if (overflow && mode == Mode::Saturating)
      value = value.negative ? integerMinimum(type) : integerMaximum(type);
    else if (overflow && mode != Mode::Checked && mode != Mode::Wrapping &&
             mode != Mode::Overflowing)
      throw std::invalid_argument("required integer constant overflows");
    return result(owner, decode(encode(value, width), type),
                  overflow &&
                      (mode == Mode::Checked || mode == Mode::Overflowing));
  };
  if (shift) {
    auto count = b.magnitude[0];
    bool overflow = count >= width;
    auto value = encode(a, width);
    if (mode == Mode::Unbounded && overflow)
      return result(owner,
                    integerLiteral(method == "shr" && a.negative ? -1 : 0));
    if (overflow && mode != Mode::Checked && mode != Mode::Wrapping &&
        mode != Mode::Overflowing)
      throw std::invalid_argument("invalid shift in constant expression");
    count %= width;
    for (std::uint64_t i = 0; i < count; ++i) {
      value = method == "shl" ? shiftLeft(value) : shiftRight(value);
      if (method == "shr" && a.negative)
        setBit(value, width - 1);
    }
    return result(owner, decode(value, type), overflow);
  }
  if (power) {
    auto exponent = b.magnitude[0];
    auto value = integerLiteral(1), factor = a;
    bool overflow = false;
    bool negative = a.negative && (exponent & 1);
    while (exponent) {
      if (exponent & 1) {
        bool carry = false;
        auto product = arithmetic("*", value, factor, carry);
        overflow |= carry || !integerLiteralFits(product, type);
        value = decode(encode(product, width), type);
      }
      exponent >>= 1;
      if (exponent) {
        bool carry = false;
        auto square = arithmetic("*", factor, factor, carry);
        overflow |= carry || !integerLiteralFits(square, type);
        factor = decode(encode(square, width), type);
      }
    }
    if (overflow && mode == Mode::Saturating)
      return result(owner,
                    negative ? integerMinimum(type) : integerMaximum(type));
    return finish(value, overflow);
  }
  if (division) {
    if (zero(b.magnitude)) {
      if (mode == Mode::Checked)
        return result(owner, {}, true);
      throw std::invalid_argument("division by zero in constant expression");
    }
    bool overflow =
        sign && a == integerMinimum(type) && b == integerLiteral(-1);
    if (overflow) {
      if (mode == Mode::Saturating)
        return result(owner, integerMaximum(type));
      if (mode == Mode::Wrapping || mode == Mode::Overflowing ||
          mode == Mode::Checked)
        return result(owner,
                      remainder ? integerLiteral(0) : integerMinimum(type),
                      mode != Mode::Wrapping);
      throw std::invalid_argument("required integer constant overflows");
    }
    auto [quotientMagnitude, remainderMagnitude] =
        divide(a.magnitude, b.magnitude);
    NumericLiteral quotient, rest;
    quotient.magnitude = quotientMagnitude;
    quotient.negative = a.negative != b.negative && !zero(quotientMagnitude);
    rest.magnitude = remainderMagnitude;
    rest.negative = a.negative && !zero(remainderMagnitude);
    if (method.ends_with("_euclid") && rest.negative) {
      quotient = arithmetic(b.negative ? "+" : "-", quotient, integerLiteral(1),
                            overflow);
      rest.magnitude = subtract(b.magnitude, rest.magnitude);
      rest.negative = false;
    }
    return finish(remainder ? rest : quotient, overflow);
  }
  bool overflow = false;
  NumericLiteral value;
  if (unaryMethod) {
    value = a;
    value.negative = method == "abs" ? false : !a.negative;
    if (zero(value.magnitude))
      value.negative = false;
  } else
    value = arithmetic(method == "add"   ? "+"
                       : method == "sub" ? "-"
                                         : "*",
                       a, b, overflow);
  return finish(value, overflow);
}
} // namespace mettle
