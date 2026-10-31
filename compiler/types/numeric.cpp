#include "types/type.h"
#include <bit>

namespace mettle {
bool isInteger(Type type) {
  return type == Type::I8 || type == Type::I16 || type == Type::I32 ||
         type == Type::I64 || type == Type::I128 || type == Type::Isize ||
         type == Type::U8 || type == Type::U16 || type == Type::U32 ||
         type == Type::U64 || type == Type::U128 || type == Type::Usize;
}
bool isSignedInteger(Type type) {
  return type == Type::I8 || type == Type::I16 || type == Type::I32 ||
         type == Type::I64 || type == Type::I128 || type == Type::Isize;
}
bool isFloating(Type type) { return type == Type::F32 || type == Type::F64; }
bool isNumeric(Type type) { return isInteger(type) || isFloating(type); }
unsigned integerWidth(Type type) {
  if (type == Type::I8 || type == Type::U8)
    return 8;
  if (type == Type::I16 || type == Type::U16)
    return 16;
  if (type == Type::I32 || type == Type::U32 || type == Type::Char)
    return 32;
  if (type == Type::I64 || type == Type::U64 || type == Type::Isize ||
      type == Type::Usize)
    return 64;
  if (type == Type::I128 || type == Type::U128)
    return 128;
  return type == Type::Bool ? 1 : 0;
}
unsigned integerWidth(Type type, unsigned pointerBits) {
  return type == Type::Usize || type == Type::Isize ? pointerBits
                                                    : integerWidth(type);
}
Type integerEquivalent(Type type, unsigned pointerBits) {
  if (type != Type::Usize && type != Type::Isize)
    return type;
  const bool sign = type == Type::Isize;
  return pointerBits == 16   ? (sign ? Type::I16 : Type::U16)
         : pointerBits == 32 ? (sign ? Type::I32 : Type::U32)
                             : (sign ? Type::I64 : Type::U64);
}
Type builtinType(std::string_view name) {
  for (auto type :
       {Type::I8, Type::I16, Type::I32, Type::I64, Type::I128, Type::Isize,
        Type::U8, Type::U16, Type::U32, Type::U64, Type::U128, Type::Usize,
        Type::F32, Type::F64, Type::Bool, Type::Char, Type::Unit, Type::Never})
    if (typeName(type) == name)
      return type;
  return Type::Unknown;
}
bool integerLiteralFits(const NumericLiteral &literal, Type type) {
  if ((!isInteger(type) && type != Type::Bool && type != Type::Char) ||
      !literal.floating.empty() || (literal.negative && !isSignedInteger(type)))
    return false;
  auto width = integerWidth(type);
  auto low = literal.magnitude[0], high = literal.magnitude[1];
  if (type == Type::Char)
    return high == 0 && low <= 0x10ffff && !(low >= 0xd800 && low <= 0xdfff);
  auto bits = high ? 128u - static_cast<unsigned>(std::countl_zero(high))
                   : 64u - static_cast<unsigned>(std::countl_zero(low));
  if (!isSignedInteger(type))
    return bits <= width;
  if (bits < width)
    return true;
  if (!literal.negative || bits != width)
    return false;
  return width > 64 ? low == 0 && high == (std::uint64_t{1} << (width - 65))
                    : high == 0 && low == (std::uint64_t{1} << (width - 1));
}
bool integerLiteralFits(const NumericLiteral &literal, Type type,
                        unsigned pointerBits) {
  return integerLiteralFits(literal, integerEquivalent(type, pointerBits));
}
bool validFloatingLiteral(std::string_view spelling) {
  // The associated constants INFINITY, NEG_INFINITY and NAN have no decimal
  // spelling; source literals cannot produce these names.
  if (spelling == "inf" || spelling == "-inf" || spelling == "nan")
    return true;
  std::size_t position = spelling.starts_with("-") ? 1 : 0;
  auto digits = [&] {
    auto start = position;
    while (position < spelling.size() && spelling[position] >= '0' &&
           spelling[position] <= '9')
      ++position;
    return position != start;
  };
  if (!digits())
    return false;
  if (position < spelling.size() && spelling[position] == '.') {
    ++position;
    if (!digits())
      return false;
  }
  if (position < spelling.size() &&
      (spelling[position] == 'e' || spelling[position] == 'E')) {
    ++position;
    if (position < spelling.size() &&
        (spelling[position] == '+' || spelling[position] == '-'))
      ++position;
    if (!digits())
      return false;
  }
  return position == spelling.size();
}
bool scalarCastAllowed(Type source, Type target) {
  return (isNumeric(source) && isNumeric(target)) ||
         ((source == Type::Bool || source == Type::Char) &&
          isInteger(target)) ||
         (source == Type::U8 && target == Type::Char);
}
} // namespace mettle
