#include "backend/llvm/numeric.h"
#include "llvm/ADT/APFloat.h"
#include "llvm/ADT/APSInt.h"
#include "llvm/Support/Error.h"
#include <vector>

namespace mettle::backend {
namespace {
const llvm::fltSemantics &semantics(Type type) {
  return type == Type::F32 ? llvm::APFloat::IEEEsingle()
                           : llvm::APFloat::IEEEdouble();
}
constexpr auto nearest = llvm::APFloat::rmNearestTiesToEven;

std::optional<llvm::APFloat> decode(const NumericConstant &value) {
  if (!validFloatingConstant(value.literal, value.type))
    return std::nullopt;
  if (value.literal.floatingBits)
    return llvm::APFloat(semantics(value.type),
                         llvm::APInt(value.type == Type::F32 ? 32 : 64,
                                     *value.literal.floatingBits));
  llvm::APFloat result(semantics(value.type));
  auto status = result.convertFromString(value.literal.floating, nearest);
  if (!status) {
    llvm::consumeError(status.takeError());
    return std::nullopt;
  }
  return result;
}
NumericConstant encode(Type type, const llvm::APFloat &value) {
  NumericConstant result;
  result.type = type;
  result.literal.floatingBits = value.bitcastToAPInt().getZExtValue();
  return result;
}
NumericConstant boolean(bool value) {
  return {Type::Bool, integerLiteral(value ? 1 : 0)};
}
llvm::APInt integerBits(const NumericConstant &value) {
  llvm::APInt result(128, llvm::ArrayRef(value.literal.magnitude));
  if (value.literal.negative)
    result = -result;
  return result.trunc(integerWidth(value.type));
}
llvm::APFloat integerFloat(Type type, std::uint64_t value) {
  llvm::APFloat result(semantics(type));
  result.convertFromAPInt(llvm::APInt(64, value), false, nearest);
  return result;
}
} // namespace

std::optional<NumericConstant>
evaluateNumeric(std::string_view operation, Type owner,
                std::span<const NumericConstant> arguments) {
  if (operation == "cast" && arguments.size() == 1) {
    const auto &source = arguments[0];
    if (isFloating(owner)) {
      if (isInteger(source.type)) {
        if (!integerLiteralFits(source.literal, source.type))
          return std::nullopt;
        llvm::APFloat result(semantics(owner));
        result.convertFromAPInt(integerBits(source),
                                isSignedInteger(source.type), nearest);
        return encode(owner, result);
      }
      auto result = decode(source);
      if (!result)
        return std::nullopt;
      bool loses = false;
      result->convert(semantics(owner), nearest, &loses);
      return encode(owner, *result);
    }
    if (isInteger(owner) && isFloating(source.type)) {
      auto input = decode(source);
      if (!input)
        return std::nullopt;
      llvm::APSInt bits(integerWidth(owner), !isSignedInteger(owner));
      bool exact = false;
      auto status =
          input->convertToInteger(bits, llvm::APFloat::rmTowardZero, &exact);
      if (status & llvm::APFloat::opInvalidOp)
        return NumericConstant{owner, input->isNaN() ? integerLiteral(0)
                                      : input->isNegative()
                                          ? integerMinimum(owner)
                                          : integerMaximum(owner)};
      NumericLiteral result;
      result.negative = bits.isSigned() && bits.isNegative();
      llvm::APInt magnitude = result.negative ? -bits : bits;
      magnitude = magnitude.zextOrTrunc(128);
      result.magnitude = {magnitude.getRawData()[0], magnitude.getRawData()[1]};
      return NumericConstant{owner, result};
    }
    return std::nullopt;
  }
  if (!isFloating(owner))
    return std::nullopt;
  if (operation == "literal" && arguments.size() == 1) {
    auto value = decode({owner, arguments[0].literal});
    return value ? std::optional(encode(owner, *value)) : std::nullopt;
  }
  if (operation == "from_bits" && arguments.size() == 1) {
    auto bitsType = owner == Type::F32 ? Type::U32 : Type::U64;
    if (arguments[0].type != bitsType ||
        !integerLiteralFits(arguments[0].literal, bitsType))
      return std::nullopt;
    llvm::APFloat result(semantics(owner),
                         llvm::APInt(owner == Type::F32 ? 32 : 64,
                                     arguments[0].literal.magnitude[0]));
    return encode(owner, result);
  }
  std::vector<llvm::APFloat> values;
  for (const auto &argument : arguments) {
    if (argument.type != owner)
      return std::nullopt;
    auto value = decode(argument);
    if (!value)
      return std::nullopt;
    values.push_back(std::move(*value));
  }
  if (values.empty())
    return std::nullopt;
  auto a = values[0];
  if (operation == "to_bits" && values.size() == 1) {
    NumericLiteral result;
    result.magnitude[0] = a.bitcastToAPInt().getZExtValue();
    return NumericConstant{owner == Type::F32 ? Type::U32 : Type::U64, result};
  }
  if (values.size() == 1) {
    if (operation == "is_nan")
      return boolean(a.isNaN());
    if (operation == "is_infinite")
      return boolean(a.isInfinity());
    if (operation == "is_finite")
      return boolean(a.isFinite());
    if (operation == "is_normal")
      return boolean(a.isNormal());
    if (operation == "is_subnormal")
      return boolean(a.isDenormal());
    if (operation == "is_sign_negative")
      return boolean(a.isNegative());
    if (operation == "is_sign_positive")
      return boolean(!a.isNegative());
    if (operation == "neg")
      a.changeSign();
    else if (operation == "abs")
      a.clearSign();
    else if (operation == "floor")
      a.roundToIntegral(llvm::APFloat::rmTowardNegative);
    else if (operation == "ceil")
      a.roundToIntegral(llvm::APFloat::rmTowardPositive);
    else if (operation == "trunc")
      a.roundToIntegral(llvm::APFloat::rmTowardZero);
    else if (operation == "round")
      a.roundToIntegral(llvm::APFloat::rmNearestTiesToAway);
    else if (operation == "round_ties_even")
      a.roundToIntegral(nearest);
    else if (operation == "next_up" || operation == "next_down")
      a.next(operation == "next_down");
    else if (operation == "fract") {
      auto integral = a;
      integral.roundToIntegral(llvm::APFloat::rmTowardZero);
      a.subtract(integral, nearest);
      if (a.isZero())
        a.copySign(values[0]);
    } else if (operation == "recip") {
      auto one = integerFloat(owner, 1);
      one.divide(a, nearest);
      a = std::move(one);
    } else if (operation == "signum") {
      if (!a.isNaN()) {
        auto one = integerFloat(owner, 1);
        one.copySign(a);
        a = std::move(one);
      }
    } else if (operation == "to_degrees" || operation == "to_radians") {
      // Runtime angle conversion rounds its coefficient in binary64 before
      // converting it to the operand width.
      llvm::APFloat pi(llvm::APFloat::IEEEdouble(),
                       llvm::APInt(64, 0x400921fb54442d18ull));
      auto degrees = integerFloat(Type::F64, 180);
      auto factor = operation == "to_degrees" ? degrees : pi;
      factor.divide(operation == "to_degrees" ? pi : degrees, nearest);
      bool loses = false;
      factor.convert(semantics(owner), nearest, &loses);
      a.multiply(factor, nearest);
    } else
      return std::nullopt;
    return encode(owner, a);
  }
  const auto &b = values[1];
  auto comparison = a.compare(b);
  if (values.size() == 2) {
    if (operation == "==")
      return boolean(comparison == llvm::APFloat::cmpEqual);
    if (operation == "!=")
      return boolean(comparison != llvm::APFloat::cmpEqual);
    if (operation == "<")
      return boolean(comparison == llvm::APFloat::cmpLessThan);
    if (operation == ">")
      return boolean(comparison == llvm::APFloat::cmpGreaterThan);
    if (operation == "<=")
      return boolean(comparison == llvm::APFloat::cmpLessThan ||
                     comparison == llvm::APFloat::cmpEqual);
    if (operation == ">=")
      return boolean(comparison == llvm::APFloat::cmpGreaterThan ||
                     comparison == llvm::APFloat::cmpEqual);
    if (operation == "+")
      a.add(b, nearest);
    else if (operation == "-")
      a.subtract(b, nearest);
    else if (operation == "*")
      a.multiply(b, nearest);
    else if (operation == "/")
      a.divide(b, nearest);
    else if (operation == "%")
      a.mod(b);
    else if (operation == "copysign")
      a.copySign(b);
    else if (operation == "min" || operation == "max") {
      bool minimum = operation == "min";
      if (a.isNaN())
        a = b;
      else if (!b.isNaN()) {
        if (a.isZero() && b.isZero())
          a = llvm::APFloat::getZero(
              semantics(owner), minimum ? a.isNegative() || b.isNegative()
                                        : a.isNegative() && b.isNegative());
        else if (comparison == (minimum ? llvm::APFloat::cmpGreaterThan
                                        : llvm::APFloat::cmpLessThan))
          a = b;
      }
    } else if (operation == "midpoint") {
      if (a.isNaN() || b.isNaN())
        a.add(b, nearest);
      else if (a.isInfinity() || b.isInfinity()) {
        if (a.isInfinity() && b.isInfinity() &&
            a.isNegative() != b.isNegative())
          a.add(b, nearest);
        else if (b.isInfinity())
          a = b;
      } else if (a.isZero() && b.isZero()) {
        a = llvm::APFloat::getZero(semantics(owner),
                                   a.isNegative() && b.isNegative());
      } else {
        auto two = integerFloat(owner, 2);
        if (a.isNegative() == b.isNegative()) {
          auto difference = b;
          difference.subtract(a, nearest);
          difference.divide(two, nearest);
          a.add(difference, nearest);
        } else {
          a.add(b, nearest);
          a.divide(two, nearest);
        }
      }
    } else
      return std::nullopt;
    return encode(owner, a);
  }
  if (values.size() == 3 && operation == "mul_add") {
    a.fusedMultiplyAdd(b, values[2], nearest);
    return encode(owner, a);
  }
  if (values.size() == 3 && operation == "clamp") {
    auto order = b.compare(values[2]);
    if (order == llvm::APFloat::cmpUnordered ||
        order == llvm::APFloat::cmpGreaterThan)
      return std::nullopt;
    if (a.compare(b) == llvm::APFloat::cmpLessThan)
      a = b;
    else if (a.compare(values[2]) == llvm::APFloat::cmpGreaterThan)
      a = values[2];
    return encode(owner, a);
  }
  return std::nullopt;
}
} // namespace mettle::backend
