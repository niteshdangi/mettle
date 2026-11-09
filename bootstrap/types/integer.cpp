#include "types/type.h"
#include <algorithm>
#include <stdexcept>

namespace mettle {
namespace {
using Magnitude = std::array<std::uint64_t, 2>;
bool zero(Magnitude a) { return a[0] == 0 && a[1] == 0; }
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
Magnitude shiftLeft(Magnitude a) {
  return {a[0] << 1, (a[1] << 1) | (a[0] >> 63)};
}
bool bit(Magnitude a, unsigned position) {
  return (a[position / 64] >> (position % 64)) & 1;
}
void setBit(Magnitude &a, unsigned position) {
  a[position / 64] |= std::uint64_t{1} << (position % 64);
}
std::pair<Magnitude, Magnitude> divide(Magnitude a, Magnitude b) {
  Magnitude quotient{}, remainder{};
  for (unsigned position = 128; position-- > 0;) {
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
  if (op == "+" || op == "-") {
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
  } else if (op == "*") {
    result.negative = a.negative != b.negative;
    auto shifted = a.magnitude;
    bool discarded = false;
    for (unsigned position = 0; position < 128; ++position) {
      if (bit(b.magnitude, position)) {
        bool carry = false;
        result.magnitude = add(result.magnitude, shifted, carry);
        overflow |= carry || discarded;
      }
      discarded |= (shifted[1] >> 63) != 0;
      shifted = shiftLeft(shifted);
    }
  } else if (op == "/" || op == "%") {
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
        bits = {(bits[0] >> 1) | (bits[1] << 63), bits[1] >> 1};
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
} // namespace mettle
