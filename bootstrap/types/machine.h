#pragma once

#include "types/type.h"

namespace mettle {
bool containsVarArgs(const TypeStore &types, Type type);
struct MachineSignature {
  enum class Shape {
    Value,
    Optional,
    Overflow,
    // (value, value): the low and high words of a widening multiply.
    Pair,
    PointerRead,
    PointerMut,
    ViewRead,
    ViewMut,
    PinRead,
    PinMut,
    Outcome,
    Ref,
    RefMut,
    TryRef,
    TryRefMut
  };
  Type value;
  Shape shape = Shape::Value;
  bool unsafeCall = false;
};
std::optional<MachineSignature>
machineSignature(const TypeStore &types, std::string_view operation,
                 std::span<const Type> operands, Type argument = Type::Unknown,
                 std::span<const Type> unpinProofs = {});
bool machineResultMatches(const TypeStore &types,
                          const MachineSignature &signature, Type result);
bool machineCastAllowed(const TypeStore &types, Type source, Type target);
bool constantFloatMethod(std::string_view name);
struct IntegerMethodResult {
  Type type = Type::Unknown;
  NumericLiteral value{};
  bool failed = false;
};
std::optional<IntegerMethodResult>
evaluateIntegerMethod(std::string_view method, Type owner,
                      std::span<const NumericLiteral> operands,
                      unsigned pointerBits, bool littleEndian);
} // namespace mettle
