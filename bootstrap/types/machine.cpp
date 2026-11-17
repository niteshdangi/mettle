#include "types/machine.h"
#include "types/layout.h"
#include "types/target.h"
#include <algorithm>
#include <functional>
#include <set>
#include <unordered_map>

namespace mettle {
MachineMethod machineMethod(std::string_view name) {
  static const std::unordered_map<std::string_view, MachineMethod> methods{
      {"abort", MachineMethod::Abort},
      {"abs", MachineMethod::Abs},
      {"abs_diff", MachineMethod::AbsDiff},
      {"acos", MachineMethod::Acos},
      {"acosh", MachineMethod::Acosh},
      {"add", MachineMethod::Add},
      {"addr", MachineMethod::Addr},
      {"addr_of", MachineMethod::AddrOf},
      {"addr_of_mut", MachineMethod::AddrOfMut},
      {"align_of", MachineMethod::AlignOf},
      {"align_of_val", MachineMethod::AlignOfVal},
      {"align_of_val_raw", MachineMethod::AlignOfValRaw},
      {"arg", MachineMethod::Arg},
      {"as_array", MachineMethod::AsArray},
      {"as_mut", MachineMethod::AsMut},
      {"as_mut_array", MachineMethod::AsMutArray},
      {"as_mut_ptr", MachineMethod::AsMutPtr},
      {"as_mut_unchecked", MachineMethod::AsMutUnchecked},
      {"as_ptr", MachineMethod::AsPtr},
      {"as_ref", MachineMethod::AsRef},
      {"as_ref_unchecked", MachineMethod::AsRefUnchecked},
      {"asin", MachineMethod::Asin},
      {"asinh", MachineMethod::Asinh},
      {"assert_unchecked", MachineMethod::AssertUnchecked},
      {"assume_init", MachineMethod::AssumeInit},
      {"assume_init_drop", MachineMethod::AssumeInitDrop},
      {"assume_init_mut", MachineMethod::AssumeInitMut},
      {"assume_init_read", MachineMethod::AssumeInitRead},
      {"assume_init_ref", MachineMethod::AssumeInitRef},
      {"atan", MachineMethod::Atan},
      {"atan2", MachineMethod::Atan2},
      {"atanh", MachineMethod::Atanh},
      {"bit_width", MachineMethod::BitWidth},
      {"black_box", MachineMethod::BlackBox},
      {"borrow", MachineMethod::Borrow},
      {"borrow_mut", MachineMethod::BorrowMut},
      {"borrowing_sub", MachineMethod::BorrowingSub},
      {"byte_offset_from", MachineMethod::ByteOffsetFrom},
      {"byte_offset_from_unsigned", MachineMethod::ByteOffsetFromUnsigned},
      {"caller_location", MachineMethod::CallerLocation},
      {"carrying_add", MachineMethod::CarryingAdd},
      {"carrying_mul", MachineMethod::CarryingMul},
      {"carrying_mul_add", MachineMethod::CarryingMulAdd},
      {"cast", MachineMethod::Cast},
      {"cast_const", MachineMethod::CastConst},
      {"cast_mut", MachineMethod::CastMut},
      {"cast_signed", MachineMethod::CastSigned},
      {"cast_unsigned", MachineMethod::CastUnsigned},
      {"cbrt", MachineMethod::Cbrt},
      {"ceil", MachineMethod::Ceil},
      {"checked_cast", MachineMethod::CheckedCast},
      {"checked_ilog", MachineMethod::CheckedIlog},
      {"checked_ilog10", MachineMethod::CheckedIlog10},
      {"checked_ilog2", MachineMethod::CheckedIlog2},
      {"checked_isqrt", MachineMethod::CheckedIsqrt},
      {"checked_next_multiple_of", MachineMethod::CheckedNextMultipleOf},
      {"checked_next_power_of_two", MachineMethod::CheckedNextPowerOfTwo},
      {"checked_pow", MachineMethod::CheckedPow},
      {"checked_signed_diff", MachineMethod::CheckedSignedDiff},
      {"clamp", MachineMethod::Clamp},
      {"clone", MachineMethod::Clone},
      {"cold_path", MachineMethod::ColdPath},
      {"compare_exchange", MachineMethod::CompareExchange},
      {"compare_exchange_weak", MachineMethod::CompareExchangeWeak},
      {"compiler_fence", MachineMethod::CompilerFence},
      {"context", MachineMethod::Context},
      {"copy", MachineMethod::Copy},
      {"copy_nonoverlapping", MachineMethod::CopyNonoverlapping},
      {"copysign", MachineMethod::Copysign},
      {"cos", MachineMethod::Cos},
      {"cosh", MachineMethod::Cosh},
      {"count_ones", MachineMethod::CountOnes},
      {"count_zeros", MachineMethod::CountZeros},
      {"div", MachineMethod::Div},
      {"div_ceil", MachineMethod::DivCeil},
      {"div_euclid", MachineMethod::DivEuclid},
      {"drop", MachineMethod::Drop},
      {"drop_in_place", MachineMethod::DropInPlace},
      {"end", MachineMethod::End},
      {"eq_ignore_ascii_case", MachineMethod::EqIgnoreAsciiCase},
      {"exp", MachineMethod::Exp},
      {"exp2", MachineMethod::Exp2},
      {"exp_m1", MachineMethod::ExpM1},
      {"expose_provenance", MachineMethod::ExposeProvenance},
      {"fence", MachineMethod::Fence},
      {"fetch_add", MachineMethod::FetchAdd},
      {"fetch_and", MachineMethod::FetchAnd},
      {"fetch_byte_add", MachineMethod::FetchByteAdd},
      {"fetch_byte_sub", MachineMethod::FetchByteSub},
      {"fetch_max", MachineMethod::FetchMax},
      {"fetch_min", MachineMethod::FetchMin},
      {"fetch_nand", MachineMethod::FetchNand},
      {"fetch_not", MachineMethod::FetchNot},
      {"fetch_or", MachineMethod::FetchOr},
      {"fetch_ptr_add", MachineMethod::FetchPtrAdd},
      {"fetch_ptr_sub", MachineMethod::FetchPtrSub},
      {"fetch_sub", MachineMethod::FetchSub},
      {"fetch_xor", MachineMethod::FetchXor},
      {"floor", MachineMethod::Floor},
      {"fn_addr", MachineMethod::FnAddr},
      {"fn_addr_eq", MachineMethod::FnAddrEq},
      {"forget", MachineMethod::Forget},
      {"fract", MachineMethod::Fract},
      {"from_be", MachineMethod::FromBe},
      {"from_be_bytes", MachineMethod::FromBeBytes},
      {"from_bits", MachineMethod::FromBits},
      {"from_le", MachineMethod::FromLe},
      {"from_le_bytes", MachineMethod::FromLeBytes},
      {"from_mut", MachineMethod::FromMut},
      {"from_ne_bytes", MachineMethod::FromNeBytes},
      {"from_ref", MachineMethod::FromRef},
      {"get", MachineMethod::Get},
      {"get_mut", MachineMethod::GetMut},
      {"get_ref", MachineMethod::GetRef},
      {"get_unchecked_mut", MachineMethod::GetUncheckedMut},
      {"highest_one", MachineMethod::HighestOne},
      {"hypot", MachineMethod::Hypot},
      {"ilog", MachineMethod::Ilog},
      {"ilog10", MachineMethod::Ilog10},
      {"ilog2", MachineMethod::Ilog2},
      {"inline", MachineMethod::Inline},
      {"into_inner", MachineMethod::IntoInner},
      {"into_inner_unchecked", MachineMethod::IntoInnerUnchecked},
      {"is_ascii", MachineMethod::IsAscii},
      {"is_ascii_alphabetic", MachineMethod::IsAsciiAlphabetic},
      {"is_ascii_alphanumeric", MachineMethod::IsAsciiAlphanumeric},
      {"is_ascii_control", MachineMethod::IsAsciiControl},
      {"is_ascii_digit", MachineMethod::IsAsciiDigit},
      {"is_ascii_graphic", MachineMethod::IsAsciiGraphic},
      {"is_ascii_hexdigit", MachineMethod::IsAsciiHexdigit},
      {"is_ascii_lowercase", MachineMethod::IsAsciiLowercase},
      {"is_ascii_punctuation", MachineMethod::IsAsciiPunctuation},
      {"is_ascii_uppercase", MachineMethod::IsAsciiUppercase},
      {"is_ascii_whitespace", MachineMethod::IsAsciiWhitespace},
      {"is_finite", MachineMethod::IsFinite},
      {"is_infinite", MachineMethod::IsInfinite},
      {"is_multiple_of", MachineMethod::IsMultipleOf},
      {"is_nan", MachineMethod::IsNan},
      {"is_negative", MachineMethod::IsNegative},
      {"is_normal", MachineMethod::IsNormal},
      {"is_null", MachineMethod::IsNull},
      {"is_positive", MachineMethod::IsPositive},
      {"is_power_of_two", MachineMethod::IsPowerOfTwo},
      {"is_sign_negative", MachineMethod::IsSignNegative},
      {"is_sign_positive", MachineMethod::IsSignPositive},
      {"is_subnormal", MachineMethod::IsSubnormal},
      {"isolate_highest_one", MachineMethod::IsolateHighestOne},
      {"isolate_lowest_one", MachineMethod::IsolateLowestOne},
      {"isqrt", MachineMethod::Isqrt},
      {"leading_ones", MachineMethod::LeadingOnes},
      {"leading_zeros", MachineMethod::LeadingZeros},
      {"ln", MachineMethod::Ln},
      {"ln_1p", MachineMethod::Ln1p},
      {"load", MachineMethod::Load},
      {"log", MachineMethod::Log},
      {"log10", MachineMethod::Log10},
      {"log2", MachineMethod::Log2},
      {"lowest_one", MachineMethod::LowestOne},
      {"make_ascii_lowercase", MachineMethod::MakeAsciiLowercase},
      {"make_ascii_uppercase", MachineMethod::MakeAsciiUppercase},
      {"max", MachineMethod::Max},
      {"midpoint", MachineMethod::Midpoint},
      {"min", MachineMethod::Min},
      {"mul", MachineMethod::Mul},
      {"mul_add", MachineMethod::MulAdd},
      {"needs_drop", MachineMethod::NeedsDrop},
      {"neg", MachineMethod::Neg},
      {"new", MachineMethod::New},
      {"new_unchecked", MachineMethod::NewUnchecked},
      {"next_arg", MachineMethod::NextArg},
      {"next_down", MachineMethod::NextDown},
      {"next_multiple_of", MachineMethod::NextMultipleOf},
      {"next_power_of_two", MachineMethod::NextPowerOfTwo},
      {"next_up", MachineMethod::NextUp},
      {"null", MachineMethod::Null},
      {"null_mut", MachineMethod::NullMut},
      {"offset", MachineMethod::Offset},
      {"offset_from", MachineMethod::OffsetFrom},
      {"offset_from_unsigned", MachineMethod::OffsetFromUnsigned},
      {"offset_of", MachineMethod::OffsetOf},
      {"overflowing_pow", MachineMethod::OverflowingPow},
      {"panic_fmt", MachineMethod::PanicFmt},
      {"panic_message", MachineMethod::PanicMessage},
      {"pow", MachineMethod::Pow},
      {"powf", MachineMethod::Powf},
      {"powi", MachineMethod::Powi},
      {"project_unchecked", MachineMethod::ProjectUnchecked},
      {"raw_get", MachineMethod::RawGet},
      {"read", MachineMethod::Read},
      {"read_unaligned", MachineMethod::ReadUnaligned},
      {"read_volatile", MachineMethod::ReadVolatile},
      {"recip", MachineMethod::Recip},
      {"rem", MachineMethod::Rem},
      {"rem_euclid", MachineMethod::RemEuclid},
      {"replace", MachineMethod::Replace},
      {"resume", MachineMethod::Resume},
      {"reverse_bits", MachineMethod::ReverseBits},
      {"rotate_left", MachineMethod::RotateLeft},
      {"rotate_right", MachineMethod::RotateRight},
      {"round", MachineMethod::Round},
      {"round_ties_even", MachineMethod::RoundTiesEven},
      {"saturating_pow", MachineMethod::SaturatingPow},
      {"select_unpredictable", MachineMethod::SelectUnpredictable},
      {"set", MachineMethod::Set},
      {"shl", MachineMethod::Shl},
      {"shr", MachineMethod::Shr},
      {"signum", MachineMethod::Signum},
      {"sin", MachineMethod::Sin},
      {"sin_cos", MachineMethod::SinCos},
      {"sinh", MachineMethod::Sinh},
      {"size_of", MachineMethod::SizeOf},
      {"size_of_val", MachineMethod::SizeOfVal},
      {"size_of_val_raw", MachineMethod::SizeOfValRaw},
      {"slice_from_raw_parts", MachineMethod::SliceFromRawParts},
      {"slice_from_raw_parts_mut", MachineMethod::SliceFromRawPartsMut},
      {"spin_loop", MachineMethod::SpinLoop},
      {"split_token_unchecked", MachineMethod::SplitTokenUnchecked},
      {"sqrt", MachineMethod::Sqrt},
      {"start", MachineMethod::Start},
      {"store", MachineMethod::Store},
      {"strict_pow", MachineMethod::StrictPow},
      {"sub", MachineMethod::Sub},
      {"suspend", MachineMethod::Suspend},
      {"swap", MachineMethod::Swap},
      {"swap_bytes", MachineMethod::SwapBytes},
      {"swap_nonoverlapping", MachineMethod::SwapNonoverlapping},
      {"take", MachineMethod::Take},
      {"tan", MachineMethod::Tan},
      {"tanh", MachineMethod::Tanh},
      {"to_ascii_lowercase", MachineMethod::ToAsciiLowercase},
      {"to_ascii_uppercase", MachineMethod::ToAsciiUppercase},
      {"to_be", MachineMethod::ToBe},
      {"to_be_bytes", MachineMethod::ToBeBytes},
      {"to_bits", MachineMethod::ToBits},
      {"to_degrees", MachineMethod::ToDegrees},
      {"to_int_unchecked", MachineMethod::ToIntUnchecked},
      {"to_le", MachineMethod::ToLe},
      {"to_le_bytes", MachineMethod::ToLeBytes},
      {"to_ne_bytes", MachineMethod::ToNeBytes},
      {"to_radians", MachineMethod::ToRadians},
      {"trailing_ones", MachineMethod::TrailingOnes},
      {"trailing_zeros", MachineMethod::TrailingZeros},
      {"transmute", MachineMethod::Transmute},
      {"transmute_copy", MachineMethod::TransmuteCopy},
      {"trunc", MachineMethod::Trunc},
      {"try_borrow", MachineMethod::TryBorrow},
      {"try_borrow_mut", MachineMethod::TryBorrowMut},
      {"try_borrow_unguarded", MachineMethod::TryBorrowUnguarded},
      {"type_id", MachineMethod::TypeId},
      {"type_name", MachineMethod::TypeName},
      {"unbounded_shl", MachineMethod::UnboundedShl},
      {"unbounded_shr", MachineMethod::UnboundedShr},
      {"unchecked_shl", MachineMethod::UncheckedShl},
      {"unchecked_shr", MachineMethod::UncheckedShr},
      {"uninit", MachineMethod::Uninit},
      {"unreachable_unchecked", MachineMethod::UnreachableUnchecked},
      {"unsigned_abs", MachineMethod::UnsignedAbs},
      {"variant_ordinal", MachineMethod::VariantOrdinal},
      {"with_addr", MachineMethod::WithAddr},
      {"with_exposed_provenance", MachineMethod::WithExposedProvenance},
      {"without_provenance", MachineMethod::WithoutProvenance},
      {"wrapping_pow", MachineMethod::WrappingPow},
      {"write", MachineMethod::Write},
      {"write_bytes", MachineMethod::WriteBytes},
      {"write_unaligned", MachineMethod::WriteUnaligned},
      {"write_volatile", MachineMethod::WriteVolatile},
      {"zeroed", MachineMethod::Zeroed},
  };
  auto found = methods.find(name);
  return found == methods.end() ? MachineMethod::Unknown : found->second;
}
MachineOperation decodeMachineOperation(std::string_view operation) {
  auto separator = operation.find('.');
  if (separator == std::string_view::npos)
    return {MachineFamily::None, machineMethod(operation)};
  static const std::unordered_map<std::string_view, MachineFamily> families{
      {"atomic", MachineFamily::Atomic},
      {"cell", MachineFamily::Cell},
      {"coroutine", MachineFamily::Coroutine},
      {"hint", MachineFamily::Hint},
      {"intrinsics", MachineFamily::Intrinsics},
      {"mem", MachineFamily::Mem},
      {"numeric", MachineFamily::Numeric},
      {"pin", MachineFamily::Pin},
      {"ptr", MachineFamily::Ptr},
      {"storage", MachineFamily::Storage},
      {"va", MachineFamily::Va},
  };
  auto found = families.find(operation.substr(0, separator));
  return {found == families.end() ? MachineFamily::Unknown : found->second,
          machineMethod(operation.substr(separator + 1))};
}
bool constantFloatMethod(std::string_view name) {
  switch (machineMethod(name)) {
  case MachineMethod::Abs:
  case MachineMethod::Ceil:
  case MachineMethod::Clamp:
  case MachineMethod::Copysign:
  case MachineMethod::Floor:
  case MachineMethod::Fract:
  case MachineMethod::FromBeBytes:
  case MachineMethod::FromBits:
  case MachineMethod::FromLeBytes:
  case MachineMethod::FromNeBytes:
  case MachineMethod::IsFinite:
  case MachineMethod::IsInfinite:
  case MachineMethod::IsNan:
  case MachineMethod::IsNormal:
  case MachineMethod::IsSignNegative:
  case MachineMethod::IsSignPositive:
  case MachineMethod::IsSubnormal:
  case MachineMethod::Max:
  case MachineMethod::Midpoint:
  case MachineMethod::Min:
  case MachineMethod::MulAdd:
  case MachineMethod::NextDown:
  case MachineMethod::NextUp:
  case MachineMethod::Recip:
  case MachineMethod::Round:
  case MachineMethod::RoundTiesEven:
  case MachineMethod::Signum:
  case MachineMethod::ToBeBytes:
  case MachineMethod::ToBits:
  case MachineMethod::ToDegrees:
  case MachineMethod::ToLeBytes:
  case MachineMethod::ToNeBytes:
  case MachineMethod::ToRadians:
  case MachineMethod::Trunc:
    return true;
  default:
    return false;
  }
}
bool containsVarArgs(const TypeStore &types, Type type) {
  std::set<Type> visited;
  std::function<bool(Type)> visit = [&](Type current) {
    if (!visited.insert(current).second)
      return false;
    if (types.isView(current) || types.isPointer(current))
      return types.inspectView(
          current, [&](const auto &view) { return visit(view.payload); });
    if (!types.isProduct(current))
      return false;
    auto product = [&](const auto &record) {
      if (record.kind == AggregateKind::VarArgs)
        return true;
      if (record.kind == AggregateKind::Array && !record.components.empty())
        return visit(record.components[0]);
      for (const auto &field : record.fields)
        if (visit(field.type))
          return true;
      return false;
    };
    return types.inspectProduct(current, product);
  };
  return visit(type);
}
bool machineCastAllowed(const TypeStore &types, Type source, Type target) {
  if (scalarCastAllowed(source, target))
    return true;
  if (fieldlessEnumeration(types, source) && isInteger(target))
    return true;
  return types.isPointer(target) &&
         ((types.isView(source) &&
           types.view(source).payload == types.pointer(target).payload &&
           (types.pointer(target).mode == ParameterMode::Read ||
            types.view(source).mode == ParameterMode::Mut)) ||
          (types.isPointer(source) &&
           (types.pointerMetadata(types.pointer(target).payload) ==
                PointerMetadata::None ||
            types.pointerMetadata(types.pointer(source).payload) ==
                types.pointerMetadata(types.pointer(target).payload))));
}
std::optional<MachineSignature>
machineSignature(const TypeStore &types, std::string_view operation,
                 std::span<const Type> operands, Type argument,
                 std::span<const Type> unpinProofs) {
  const auto operationCode = decodeMachineOperation(operation);
  using Shape = MachineSignature::Shape;
  auto signature = [](Type value, Shape shape = Shape::Value,
                      bool unsafeCall = false) {
    return std::optional<MachineSignature>{{value, shape, unsafeCall}};
  };
  if ((operationCode.family == MachineFamily::Va)) {
    auto cursor = [&](Type type) {
      return types.isProduct(type) &&
             types.product(type).kind == AggregateKind::VarArgs;
    };
    if (operationCode ==
        MachineOperation{MachineFamily::Va, MachineMethod::Start})
      return operands.empty() && cursor(argument) ? signature(argument)
                                                  : std::nullopt;
    if (operands.size() != 1)
      return std::nullopt;
    if (operationCode ==
        MachineOperation{MachineFamily::Va, MachineMethod::End})
      return cursor(operands[0]) ? signature(Type::Unit) : std::nullopt;
    if (!types.isView(operands[0]) || !cursor(types.view(operands[0]).payload))
      return std::nullopt;
    if (operationCode ==
        MachineOperation{MachineFamily::Va, MachineMethod::Copy})
      return signature(types.view(operands[0]).payload);
    if (operationCode ==
        MachineOperation{MachineFamily::Va, MachineMethod::NextArg}) {
      bool eligible = argument == Type::I32 || argument == Type::U32 ||
                      argument == Type::I64 || argument == Type::U64 ||
                      argument == Type::I128 || argument == Type::U128 ||
                      argument == Type::Isize || argument == Type::Usize ||
                      argument == Type::F64 || types.isParameter(argument) ||
                      (types.isPointer(argument) &&
                       types.pointerMetadata(types.pointer(argument).payload) ==
                           PointerMetadata::None);
      return eligible && types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(argument, Shape::Value, true)
                 : std::nullopt;
    }
    if (operationCode !=
            MachineOperation{MachineFamily::Va, MachineMethod::Arg} ||
        types.view(operands[0]).mode != ParameterMode::Mut)
      return std::nullopt;
    std::set<Type> active;
    std::function<bool(Type)> compatible = [&](Type type) {
      if (!types.isCopy(type))
        return false;
      if (isNumeric(type) || type == Type::Char)
        return true;
      if (nativeVector(types, type))
        return true;
      if (types.isPointer(type))
        return types.pointerMetadata(types.pointer(type).payload) ==
               PointerMetadata::None;
      if (types.isFunctionPointer(type))
        return types.callable(type).abi == "C" ||
               types.callable(type).abi == "C-unwind" ||
               types.callable(type).abi == "system";
      if (!types.isProduct(type) || !active.insert(type).second)
        return false;
      const auto &record = types.product(type);
      bool valid = record.layout.kind != LayoutKind::Native ||
                   record.kind == AggregateKind::Array;
      if (record.kind == AggregateKind::Array && !record.components.empty()) {
        auto element = record.components[0];
        valid &= compatible(element) || element == Type::Unit ||
                 element == Type::Bool || element == Type::Char;
      } else
        for (const auto &field : record.fields)
          valid &= compatible(field.type) || field.type == Type::Unit ||
                   field.type == Type::Bool || field.type == Type::Char;
      active.erase(type);
      return valid;
    };
    Type promoted = argument;
    while (types.isProduct(promoted) &&
           types.product(promoted).layout.kind == LayoutKind::Transparent) {
      auto next = Type::Unit;
      const auto &record = types.product(promoted);
      for (std::size_t i = record.kind == AggregateKind::Enumeration ? 1 : 0;
           i < record.fields.size(); ++i)
        if (auto layout = objectLayout(types, record.fields[i].type);
            layout && layout->size)
          next = record.fields[i].type;
      promoted = next;
    }
    if (fieldlessEnumeration(types, promoted))
      promoted = types.product(promoted).layout.tag;
    bool promotion = promoted == Type::Bool || promoted == Type::F32 ||
                     (isInteger(promoted) && integerWidth(promoted) < 32);
    return !promotion && compatible(argument)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  }
  auto unpin = [&](Type type) {
    return types.isUnpin(type) ||
           std::find(unpinProofs.begin(), unpinProofs.end(), type) !=
               unpinProofs.end();
  };
  if ((operationCode.family == MachineFamily::Cell)) {
    if (!types.isProduct(argument))
      return std::nullopt;
    const auto &cell = types.product(argument);
    auto methodCode = operationCode.method;
    bool guarded =
        cell.kind == AggregateKind::Ref || cell.kind == AggregateKind::RefMut;
    if (guarded) {
      if (operands.empty() || !types.isView(operands[0]) ||
          types.view(operands[0]).payload != argument)
        return std::nullopt;
      auto owner = types.view(cell.components[0]).payload;
      auto payload = types.product(owner).components[0];
      if (methodCode == MachineMethod::ProjectUnchecked)
        return operands.size() == 2 && types.isPointer(operands[1]) &&
                       types.pointer(operands[1]).mode ==
                           (cell.kind == AggregateKind::Ref
                                ? ParameterMode::Read
                                : ParameterMode::Mut)
                   ? signature(types.pointer(operands[1]).payload,
                               cell.kind == AggregateKind::Ref
                                   ? Shape::RefProjection
                                   : Shape::RefMutProjection,
                               true)
                   : std::nullopt;
      if (operands.size() != 1)
        return std::nullopt;
      if (methodCode == MachineMethod::GetRef)
        return signature(payload, Shape::ViewRead);
      if (methodCode == MachineMethod::GetMut &&
          cell.kind == AggregateKind::RefMut &&
          types.view(operands[0]).mode == ParameterMode::Mut)
        return signature(payload, Shape::ViewMut);
      if (methodCode == MachineMethod::Clone && cell.kind == AggregateKind::Ref)
        return signature(owner, Shape::Ref);
      if (methodCode == MachineMethod::SplitTokenUnchecked)
        return signature(
            owner, cell.kind == AggregateKind::Ref ? Shape::Ref : Shape::RefMut,
            true);
      return std::nullopt;
    }
    if (cell.kind != AggregateKind::Cell && cell.kind != AggregateKind::RefCell)
      return std::nullopt;
    auto payload = cell.components[0];
    if (methodCode == MachineMethod::New)
      return operands.size() == 1 && operands[0] == payload &&
                     types.isSized(payload)
                 ? signature(argument)
                 : std::nullopt;
    if (methodCode == MachineMethod::IntoInner)
      return operands.size() == 1 && operands[0] == argument &&
                     types.isSized(payload)
                 ? signature(payload)
                 : std::nullopt;
    if (operands.empty() || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    if (methodCode == MachineMethod::GetMut)
      return operands.size() == 1 &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::AsPtr)
      return operands.size() == 1 ? signature(payload, Shape::PointerMut)
                                  : std::nullopt;
    if (methodCode == MachineMethod::Get)
      return cell.kind == AggregateKind::Cell && operands.size() == 1 &&
                     types.isCopy(payload)
                 ? signature(payload)
                 : std::nullopt;
    if (methodCode == MachineMethod::Replace ||
        methodCode == MachineMethod::Set)
      return operands.size() == 2 && operands[1] == payload &&
                     types.isSized(payload) &&
                     (methodCode != MachineMethod::Set ||
                      cell.kind == AggregateKind::Cell)
                 ? signature(methodCode == MachineMethod::Set ? Type::Unit
                                                              : payload)
                 : std::nullopt;
    if (methodCode == MachineMethod::Swap)
      return operands.size() == 2 && types.isSized(payload) &&
                     types.isView(operands[1]) &&
                     types.view(operands[1]).payload == argument
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (cell.kind == AggregateKind::RefCell && operands.size() == 1) {
      if (methodCode == MachineMethod::Borrow)
        return signature(argument, Shape::Ref);
      if (methodCode == MachineMethod::BorrowMut)
        return signature(argument, Shape::RefMut);
      if (methodCode == MachineMethod::TryBorrow)
        return signature(argument, Shape::TryRef);
      if (methodCode == MachineMethod::TryBorrowMut)
        return signature(argument, Shape::TryRefMut);
      if (methodCode == MachineMethod::TryBorrowUnguarded)
        return signature(payload, Shape::UnguardedRef, true);
    }
    return std::nullopt;
  }
  if (auto target = targetOperation(operation)) {
    if (!nativeVector(types, argument) ||
        types.name(argument) != target->vector ||
        operands.size() != target->arguments)
      return std::nullopt;
    using K = TargetOperation::Kind;
    for (std::size_t i = 0; i < operands.size(); ++i) {
      auto actual = operands[i];
      auto expected = argument;
      if (target->kind == K::Splat || target->kind == K::Set ||
          (target->kind == K::Insert && i == 0))
        expected = target->element;
      else if (target->kind == K::Load ||
               (target->kind == K::Store && i == 0)) {
        auto descriptor = *targetVector(target->vector);
        auto pointee =
            descriptor.arch == TargetArch::X86_64 ? argument : target->element;
        if (!types.isPointer(actual) ||
            types.pointer(actual).payload != pointee ||
            (target->kind == K::Store &&
             types.pointer(actual).mode != ParameterMode::Mut))
          return std::nullopt;
        continue;
      } else if ((target->kind == K::Extract && i == 1) ||
                 (target->kind == K::Insert && i == 2))
        expected = Type::I32;
      if (actual != expected)
        return std::nullopt;
    }
    return signature(target->kind == K::Store     ? Type::Unit
                     : target->kind == K::Extract ? target->element
                                                  : argument,
                     Shape::Value, true);
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Forget})
    return operands.size() == 1 ? signature(Type::Unit) : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Drop})
    return operands.size() == 1 && types.isSized(operands[0])
               ? signature(Type::Unit)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::OffsetOf})
    return operands.empty() && types.isProduct(argument)
               ? signature(Type::Usize)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Hint, MachineMethod::BlackBox})
    return operands.size() == 1 && operands[0] == argument ? signature(argument)
                                                           : std::nullopt;
  if (operationCode ==
          MachineOperation{MachineFamily::Hint, MachineMethod::SpinLoop} ||
      operationCode ==
          MachineOperation{MachineFamily::Hint, MachineMethod::ColdPath})
    return operands.empty() ? signature(Type::Unit) : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Hint, MachineMethod::AssertUnchecked})
    return operands.size() == 1 && operands[0] == Type::Bool
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Hint, MachineMethod::SelectUnpredictable})
    return operands.size() == 3 && operands[0] == Type::Bool &&
                   operands[1] == argument && operands[2] == argument &&
                   types.isSized(argument)
               ? signature(argument)
               : std::nullopt;
  if (operationCode == MachineOperation{MachineFamily::Hint,
                                        MachineMethod::UnreachableUnchecked})
    return operands.empty() ? signature(Type::Never, Shape::Value, true)
                            : std::nullopt;
  for (auto operand : operands)
    if (containsVarArgs(types, operand))
      return std::nullopt;
  if ((operationCode ==
           MachineOperation{MachineFamily::Mem, MachineMethod::Zeroed} ||
       operationCode ==
           MachineOperation{MachineFamily::Mem, MachineMethod::Transmute} ||
       operationCode == MachineOperation{MachineFamily::Mem,
                                         MachineMethod::TransmuteCopy}) &&
      containsVarArgs(types, argument))
    return std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::Abort})
    return operands.empty() ? signature(Type::Never) : std::nullopt;
  if ((operationCode.family == MachineFamily::Coroutine)) {
    bool state = types.isProduct(argument) &&
                 types.product(argument).kind == AggregateKind::Coroutine;
    if (operationCode ==
        MachineOperation{MachineFamily::Coroutine, MachineMethod::Suspend})
      return operands.empty() ? signature(Type::Unit) : std::nullopt;
    if (operationCode ==
        MachineOperation{MachineFamily::Coroutine, MachineMethod::Context})
      return operands.empty() ? signature(Type::U8, Shape::PointerMut)
                              : std::nullopt;
    if (operationCode ==
        MachineOperation{MachineFamily::Coroutine, MachineMethod::Start})
      return state && operands.size() == 1 &&
                     operands[0] == types.product(argument).components[1]
                 ? signature(argument, Shape::Value, true)
                 : std::nullopt;
    if (operationCode ==
        MachineOperation{MachineFamily::Coroutine, MachineMethod::Resume})
      return state && operands.size() == 2 && types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut &&
                     types.isPointer(operands[1]) &&
                     types.pointer(operands[1]).payload == Type::U8 &&
                     types.pointer(operands[1]).mode == ParameterMode::Mut
                 ? signature(types.product(argument).components[0],
                             Shape::Optional, true)
                 : std::nullopt;
    return std::nullopt;
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::PanicFmt}) {
    auto bytePointer = [&](Type type, ParameterMode mode) {
      return types.isPointer(type) && types.pointer(type).payload == Type::U8 &&
             types.pointer(type).mode == mode;
    };
    auto callback = [&](Type type) {
      return types.isFunctionPointer(type) && types.callable(type).abi == "C" &&
             types.callable(type).result == Type::Unit &&
             types.callable(type).error == Type::Unknown &&
             !types.callable(type).variadic &&
             types.callable(type).targetFeatures.empty() &&
             std::all_of(types.callable(type).parameters.begin(),
                         types.callable(type).parameters.end(),
                         [](const auto &parameter) {
                           return parameter.mode == ParameterMode::Value;
                         });
    };
    if (operands.size() != 2 || !types.isView(operands[0]) ||
        types.view(operands[0]).mode != ParameterMode::Read ||
        !types.isProduct(types.view(operands[0]).payload) ||
        types.product(types.view(operands[0]).payload).name !=
            "core::fmt::Message" ||
        !callback(operands[1]))
      return std::nullopt;
    const auto &render = types.callable(operands[1]);
    if (render.parameters.size() != 3 ||
        !bytePointer(render.parameters[0].type, ParameterMode::Mut) ||
        !bytePointer(render.parameters[2].type, ParameterMode::Mut) ||
        !callback(render.parameters[1].type))
      return std::nullopt;
    const auto &write = types.callable(render.parameters[1].type);
    if (write.parameters.size() != 3 ||
        !bytePointer(write.parameters[0].type, ParameterMode::Mut) ||
        !bytePointer(write.parameters[1].type, ParameterMode::Read) ||
        write.parameters[2].type != Type::U64)
      return std::nullopt;
    return signature(Type::Never, Shape::Value, true);
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::PanicMessage})
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.isSlice(types.view(operands[0]).payload) &&
                   types.slice(types.view(operands[0]).payload).element ==
                       Type::U8
               ? signature(Type::Never)
               : std::nullopt;
  auto exclusive = [&](Type type) {
    return types.isView(type) && types.view(type).mode == ParameterMode::Mut &&
           types.view(type).payload == argument && types.contains(argument) &&
           types.isSized(argument);
  };
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Replace})
    return operands.size() == 2 && exclusive(operands[0]) &&
                   operands[1] == argument
               ? signature(argument)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Swap})
    return operands.size() == 2 && exclusive(operands[0]) &&
                   operands[1] == operands[0]
               ? signature(Type::Unit)
               : std::nullopt;
  if (operationCode ==
          MachineOperation{MachineFamily::Mem, MachineMethod::SizeOfVal} ||
      operationCode ==
          MachineOperation{MachineFamily::Mem, MachineMethod::AlignOfVal})
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.view(operands[0]).payload == argument &&
                   types.contains(argument) &&
                   (types.isSized(argument) ||
                    types.pointerMetadata(argument) != PointerMetadata::None)
               ? signature(Type::Usize)
               : std::nullopt;
  if (operationCode ==
          MachineOperation{MachineFamily::Mem, MachineMethod::SizeOfValRaw} ||
      operationCode ==
          MachineOperation{MachineFamily::Mem, MachineMethod::AlignOfValRaw})
    return operands.size() == 1 && types.isPointer(operands[0]) &&
                   types.pointer(operands[0]).payload == argument &&
                   types.contains(argument) &&
                   (types.isSized(argument) ||
                    types.pointerMetadata(argument) != PointerMetadata::None)
               ? signature(Type::Usize, Shape::Value, true)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Zeroed})
    return operands.empty() && types.contains(argument) &&
                   types.isSized(argument)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::Transmute}) {
    if (operands.size() != 1 || !types.contains(argument) ||
        !types.isSized(argument) || !types.isSized(operands[0]))
      return std::nullopt;
    auto source = objectLayout(types, operands[0]);
    auto target = objectLayout(types, argument);
    auto payload = [&](Type type) {
      while (types.isProduct(type) &&
             types.product(type).kind == AggregateKind::Uninit)
        type = types.product(type).components[0];
      return type;
    };
    std::function<bool(Type, Type)> sameRepresentation = [&](Type left,
                                                             Type right) {
      left = payload(left);
      right = payload(right);
      if (left == right)
        return true;
      return types.isProduct(left) && types.isProduct(right) &&
             types.product(left).kind == AggregateKind::Array &&
             types.product(right).kind == AggregateKind::Array &&
             types.product(left).arrayCount != Type::Unknown &&
             types.product(left).arrayCount ==
                 types.product(right).arrayCount &&
             sameRepresentation(types.product(left).components[0],
                                types.product(right).components[0]);
    };
    return sameRepresentation(argument, operands[0]) ||
                   (source && target && source->size == target->size)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  }
  if ((operationCode.family == MachineFamily::Atomic)) {
    auto ordering = [&](Type type) {
      return types.isProduct(type) &&
             types.product(type).kind == AggregateKind::Ordering;
    };
    auto method = operation.substr(7);
    auto methodCode = operationCode.method;
    if (methodCode == MachineMethod::Fence ||
        methodCode == MachineMethod::CompilerFence)
      return operands.size() == 1 && ordering(operands[0])
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (methodCode == MachineMethod::New)
      return types.isProduct(argument) &&
                     types.product(argument).kind == AggregateKind::Atomic &&
                     operands.size() == 1 &&
                     operands[0] == types.product(argument).components[0]
                 ? signature(argument)
                 : std::nullopt;
    bool raw = method.starts_with("raw_");
    if (raw) {
      method.remove_prefix(4);
      methodCode = machineMethod(method);
    }
    if (operands.empty())
      return std::nullopt;
    Type payload = Type::Unknown, wrapper = Type::Unknown;
    if (raw && types.isPointer(operands[0]))
      payload = types.pointer(operands[0]).payload;
    else {
      wrapper = types.isView(operands[0]) ? types.view(operands[0]).payload
                                          : operands[0];
      if (!types.isProduct(wrapper) ||
          types.product(wrapper).kind != AggregateKind::Atomic)
        return std::nullopt;
      payload = types.product(wrapper).components[0];
    }
    bool scalar =
        isInteger(payload) || payload == Type::Bool || types.isPointer(payload);
    if (!scalar || (isInteger(payload) && integerWidth(payload) > 64))
      return std::nullopt;
    if (methodCode == MachineMethod::IntoInner)
      return !raw && operands.size() == 1 && operands[0] == wrapper
                 ? signature(payload)
                 : std::nullopt;
    if (methodCode == MachineMethod::AsPtr)
      return !raw && operands.size() == 1
                 ? signature(payload, Shape::PointerMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::GetMut)
      return !raw && operands.size() == 1 && types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (!raw && !types.isView(operands[0]))
      return std::nullopt;
    if (raw && methodCode != MachineMethod::Load &&
        types.pointer(operands[0]).mode != ParameterMode::Mut)
      return std::nullopt;
    if (methodCode == MachineMethod::Load)
      return operands.size() == 2 && ordering(operands[1])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    if (methodCode == MachineMethod::Store)
      return operands.size() == 3 && operands[1] == payload &&
                     ordering(operands[2])
                 ? signature(Type::Unit, Shape::Value, raw)
                 : std::nullopt;
    if (methodCode == MachineMethod::CompareExchange ||
        methodCode == MachineMethod::CompareExchangeWeak)
      return operands.size() == 5 && operands[1] == payload &&
                     operands[2] == payload && ordering(operands[3]) &&
                     ordering(operands[4])
                 ? signature(payload, Shape::Outcome, raw)
                 : std::nullopt;
    if (methodCode == MachineMethod::FetchNot)
      return !raw && payload == Type::Bool && operands.size() == 2 &&
                     ordering(operands[1])
                 ? signature(payload)
                 : std::nullopt;
    bool pointerMask =
        types.isPointer(payload) && (methodCode == MachineMethod::FetchAnd ||
                                     methodCode == MachineMethod::FetchOr ||
                                     methodCode == MachineMethod::FetchXor);
    if (methodCode == MachineMethod::Swap ||
        methodCode == MachineMethod::FetchAnd ||
        methodCode == MachineMethod::FetchOr ||
        methodCode == MachineMethod::FetchXor ||
        methodCode == MachineMethod::FetchNand ||
        ((methodCode == MachineMethod::FetchAdd ||
          methodCode == MachineMethod::FetchSub ||
          methodCode == MachineMethod::FetchMin ||
          methodCode == MachineMethod::FetchMax) &&
         isInteger(payload)))
      return operands.size() == 3 &&
                     operands[1] == (pointerMask ? Type::Usize : payload) &&
                     ordering(operands[2])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    if (methodCode == MachineMethod::FetchPtrAdd ||
        methodCode == MachineMethod::FetchPtrSub ||
        methodCode == MachineMethod::FetchByteAdd ||
        methodCode == MachineMethod::FetchByteSub)
      return types.isPointer(payload) && operands.size() == 3 &&
                     operands[1] == Type::Usize && ordering(operands[2])
                 ? signature(payload, Shape::Value, raw)
                 : std::nullopt;
    return std::nullopt;
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Pin, MachineMethod::Inline})
    return operands.size() == 1 && types.isSized(operands[0])
               ? signature(operands[0], Shape::PinMut)
               : std::nullopt;
  if (operationCode ==
          MachineOperation{MachineFamily::Pin, MachineMethod::New} ||
      operationCode ==
          MachineOperation{MachineFamily::Pin, MachineMethod::NewUnchecked})
    return operands.size() == 1 && types.isView(operands[0]) &&
                   (operationCode ==
                        MachineOperation{MachineFamily::Pin,
                                         MachineMethod::NewUnchecked} ||
                    unpin(types.view(operands[0]).payload))
               ? signature(types.view(operands[0]).payload,
                           types.view(operands[0]).mode == ParameterMode::Mut
                               ? Shape::PinMut
                               : Shape::PinRead,
                           operationCode ==
                               MachineOperation{MachineFamily::Pin,
                                                MachineMethod::NewUnchecked})
               : std::nullopt;
  if ((operationCode.family == MachineFamily::Pin)) {
    auto method = operation.substr(4);
    auto methodCode = operationCode.method;
    if (!types.isProduct(argument) ||
        types.product(argument).kind != AggregateKind::Pin)
      return std::nullopt;
    auto view = types.product(argument).components[0];
    auto payload = types.view(view).payload;
    if (methodCode == MachineMethod::IntoInner ||
        methodCode == MachineMethod::IntoInnerUnchecked)
      return operands.size() == 1 && operands[0] == argument &&
                     (methodCode == MachineMethod::IntoInnerUnchecked ||
                      unpin(payload))
                 ? signature(view, Shape::Value,
                             methodCode == MachineMethod::IntoInnerUnchecked)
                 : std::nullopt;
    if (operands.size() != 1 || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    if (methodCode == MachineMethod::AsRef)
      return signature(payload, Shape::PinRead);
    if (methodCode == MachineMethod::GetRef)
      return signature(payload, Shape::ViewRead);
    bool exclusive = types.view(view).mode == ParameterMode::Mut &&
                     types.view(operands[0]).mode == ParameterMode::Mut;
    if (method.starts_with("project.") && types.isProduct(payload) &&
        !types.isSum(payload)) {
      const auto &record = types.product(payload);
      auto name = method.substr(8);
      for (std::size_t field = 0; field < record.fields.size(); ++field)
        if (record.fields[field].name == name) {
          if (record.layout.packing) {
            auto owner = objectLayout(types, payload);
            auto member = objectLayout(types, record.fields[field].type);
            if (!owner || !member || owner->alignment < member->alignment ||
                owner->fields[field] % member->alignment != 0)
              return std::nullopt;
          }
          bool pinned = std::find(record.layout.pinnedFields.begin(),
                                  record.layout.pinnedFields.end(),
                                  field) != record.layout.pinnedFields.end();
          return signature(record.fields[field].type,
                           pinned
                               ? (exclusive ? Shape::PinMut : Shape::PinRead)
                               : (exclusive ? Shape::ViewMut : Shape::ViewRead),
                           record.layout.unionType);
        }
    }
    if (methodCode == MachineMethod::AsMut)
      return exclusive ? signature(payload, Shape::PinMut) : std::nullopt;
    if (methodCode == MachineMethod::GetMut ||
        methodCode == MachineMethod::GetUncheckedMut)
      return exclusive && (methodCode == MachineMethod::GetUncheckedMut ||
                           unpin(payload))
                 ? signature(payload, Shape::ViewMut,
                             methodCode == MachineMethod::GetUncheckedMut)
                 : std::nullopt;
    return std::nullopt;
  }
  if ((operationCode.family == MachineFamily::Storage)) {
    auto methodCode = operationCode.method;
    if (!types.isProduct(argument))
      return std::nullopt;
    const auto &storage = types.product(argument);
    if (storage.kind != AggregateKind::Uninit &&
        storage.kind != AggregateKind::ManualDrop &&
        storage.kind != AggregateKind::UnsafeCell)
      return std::nullopt;
    auto payload = storage.components[0];
    if (methodCode == MachineMethod::RawGet)
      return storage.kind == AggregateKind::UnsafeCell &&
                     operands.size() == 1 && types.isPointer(operands[0]) &&
                     types.pointer(operands[0]).payload == argument
                 ? signature(payload, Shape::PointerMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::FromMut)
      return storage.kind == AggregateKind::UnsafeCell &&
                     operands.size() == 1 && types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut &&
                     types.view(operands[0]).payload == payload
                 ? signature(argument, Shape::ViewMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::New)
      return operands.size() == 1 && operands[0] == payload &&
                     types.isSized(payload)
                 ? signature(argument)
                 : std::nullopt;
    if (methodCode == MachineMethod::Uninit ||
        methodCode == MachineMethod::Zeroed)
      return operands.empty() && storage.kind == AggregateKind::Uninit
                 ? signature(argument)
                 : std::nullopt;
    if (methodCode == MachineMethod::AssumeInit ||
        methodCode == MachineMethod::IntoInner)
      return operands.size() == 1 && operands[0] == argument &&
                     (methodCode == MachineMethod::IntoInner
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::Value,
                             methodCode == MachineMethod::AssumeInit)
                 : std::nullopt;
    if (operands.empty() || !types.isView(operands[0]) ||
        types.view(operands[0]).payload != argument)
      return std::nullopt;
    bool exclusive = types.view(operands[0]).mode == ParameterMode::Mut;
    if (methodCode == MachineMethod::Drop ||
        methodCode == MachineMethod::AssumeInitDrop)
      return storage.kind == (methodCode == MachineMethod::Drop
                                  ? AggregateKind::ManualDrop
                                  : AggregateKind::Uninit) &&
                     exclusive && operands.size() == 1
                 ? signature(Type::Unit, Shape::Value, true)
                 : std::nullopt;
    if (methodCode == MachineMethod::Take ||
        methodCode == MachineMethod::AssumeInitRead)
      return operands.size() == 1 &&
                     (methodCode == MachineMethod::Take
                          ? storage.kind == AggregateKind::ManualDrop &&
                                exclusive
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::Value, true)
                 : std::nullopt;
    if (methodCode == MachineMethod::Write)
      return storage.kind == AggregateKind::Uninit && operands.size() == 2 &&
                     exclusive && operands[1] == payload
                 ? signature(payload, Shape::ViewMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::AsPtr)
      return operands.size() == 1 ? signature(payload, Shape::PointerRead)
                                  : std::nullopt;
    if (methodCode == MachineMethod::AsMutPtr ||
        methodCode == MachineMethod::Get)
      return operands.size() == 1 &&
                     (methodCode == MachineMethod::Get
                          ? storage.kind == AggregateKind::UnsafeCell
                          : exclusive)
                 ? signature(payload, Shape::PointerMut)
                 : std::nullopt;
    if (methodCode == MachineMethod::GetRef ||
        methodCode == MachineMethod::AssumeInitRef)
      return operands.size() == 1 &&
                     (methodCode == MachineMethod::GetRef
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::ViewRead,
                             methodCode == MachineMethod::AssumeInitRef ||
                                 storage.kind == AggregateKind::UnsafeCell)
                 : std::nullopt;
    if (methodCode == MachineMethod::GetMut ||
        methodCode == MachineMethod::AssumeInitMut)
      return operands.size() == 1 && exclusive &&
                     (methodCode == MachineMethod::GetMut
                          ? storage.kind != AggregateKind::Uninit
                          : storage.kind == AggregateKind::Uninit)
                 ? signature(payload, Shape::ViewMut,
                             methodCode == MachineMethod::AssumeInitMut)
                 : std::nullopt;
    return std::nullopt;
  }
  if (operationCode ==
          MachineOperation{MachineFamily::None, MachineMethod::SizeOf} ||
      operationCode ==
          MachineOperation{MachineFamily::None, MachineMethod::AlignOf} ||
      operationCode ==
          MachineOperation{MachineFamily::None, MachineMethod::NeedsDrop} ||
      operationCode ==
          MachineOperation{MachineFamily::None, MachineMethod::TypeId}) {
    if (!operands.empty() || !types.contains(argument) ||
        (operationCode !=
             MachineOperation{MachineFamily::None, MachineMethod::TypeId} &&
         !types.isSized(argument)))
      return std::nullopt;
    return signature(operationCode == MachineOperation{MachineFamily::None,
                                                       MachineMethod::NeedsDrop}
                         ? Type::Bool
                     : operationCode == MachineOperation{MachineFamily::None,
                                                         MachineMethod::TypeId}
                         ? Type::U64
                         : Type::Usize);
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::TypeName}) {
    auto text = types.findProduct("core::text::Text");
    return operands.empty() && types.contains(argument) && text
               ? signature(*text, Shape::ViewReadStatic)
               : std::nullopt;
  }
  if (operationCode == MachineOperation{MachineFamily::Intrinsics,
                                        MachineMethod::CallerLocation}) {
    if (!operands.empty() || !types.isProduct(argument))
      return std::nullopt;
    const auto &record = types.product(argument);
    if (record.kind != AggregateKind::Product || record.fields.size() != 3 ||
        record.layout.kind != LayoutKind::Native || record.layout.alignment ||
        record.layout.packing || record.layout.unionType ||
        !types.isCopy(argument))
      return std::nullopt;
    auto file = record.fields[0].type;
    return types.isView(file) && types.view(file).mode == ParameterMode::Read &&
                   types.isSlice(types.view(file).payload) &&
                   types.slice(types.view(file).payload).element == Type::U8 &&
                   record.fields[1].type == Type::U64 &&
                   record.fields[2].type == Type::U64
               ? signature(argument)
               : std::nullopt;
  }
  if (operationCode == MachineOperation{MachineFamily::Intrinsics,
                                        MachineMethod::VariantOrdinal})
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.view(operands[0]).payload == argument &&
                   types.isSized(argument)
               ? signature(Type::Usize)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Intrinsics, MachineMethod::FnAddr})
    return operands.size() == 1 && (types.isFunctionPointer(operands[0]) ||
                                    (types.isParameter(operands[0]) &&
                                     types.parameter(operands[0]).kind ==
                                         TypeParameterKind::Type))
               ? signature(Type::Usize)
               : std::nullopt;
  if (operationCode ==
      MachineOperation{MachineFamily::Ptr, MachineMethod::FnAddrEq}) {
    auto callable = [&](Type type) {
      return types.isFunctionPointer(type) ||
             (types.isParameter(type) &&
              types.parameter(type).kind == TypeParameterKind::Type);
    };
    return operands.size() == 2 && callable(operands[0]) &&
                   callable(operands[1])
               ? signature(Type::Bool)
               : std::nullopt;
  }
  if (operationCode ==
      MachineOperation{MachineFamily::Mem, MachineMethod::TransmuteCopy})
    return operands.size() == 1 && types.isView(operands[0]) &&
                   types.view(operands[0]).mode == ParameterMode::Read &&
                   types.isSized(types.view(operands[0]).payload) &&
                   types.isSized(argument)
               ? signature(argument, Shape::Value, true)
               : std::nullopt;
  if (operationCode == MachineOperation{MachineFamily::Ptr,
                                        MachineMethod::SliceFromRawParts} ||
      operationCode == MachineOperation{MachineFamily::Ptr,
                                        MachineMethod::SliceFromRawPartsMut}) {
    bool exclusive = operation.ends_with("_mut");
    return operands.size() == 2 && types.isPointer(operands[0]) &&
                   (!exclusive ||
                    types.pointer(operands[0]).mode == ParameterMode::Mut) &&
                   types.isSized(types.pointer(operands[0]).payload) &&
                   operands[1] == Type::Usize && types.isSlice(argument) &&
                   types.slice(argument).element ==
                       types.pointer(operands[0]).payload
               ? signature(argument,
                           exclusive ? Shape::PointerMut : Shape::PointerRead)
               : std::nullopt;
  }
  if (operationCode ==
          MachineOperation{MachineFamily::Ptr, MachineMethod::Null} ||
      operationCode ==
          MachineOperation{MachineFamily::Ptr, MachineMethod::NullMut} ||
      operationCode == MachineOperation{MachineFamily::Ptr,
                                        MachineMethod::WithoutProvenance} ||
      operationCode == MachineOperation{MachineFamily::Ptr,
                                        MachineMethod::WithExposedProvenance}) {
    bool address = operationCode != MachineOperation{MachineFamily::Ptr,
                                                     MachineMethod::Null} &&
                   operationCode != MachineOperation{MachineFamily::Ptr,
                                                     MachineMethod::NullMut};
    if (!types.contains(argument) ||
        (!(operationCode ==
               MachineOperation{MachineFamily::Ptr, MachineMethod::Null} ||
           operationCode ==
               MachineOperation{MachineFamily::Ptr, MachineMethod::NullMut}) &&
         !types.isSized(argument)) ||
        ((operationCode ==
              MachineOperation{MachineFamily::Ptr, MachineMethod::Null} ||
          operationCode ==
              MachineOperation{MachineFamily::Ptr, MachineMethod::NullMut}) &&
         !types.isThin(argument)) ||
        operands.size() != (address ? 1u : 0u) ||
        (address && operands[0] != Type::Usize))
      return std::nullopt;
    return signature(argument,
                     operationCode == MachineOperation{MachineFamily::Ptr,
                                                       MachineMethod::NullMut}
                         ? Shape::PointerMut
                         : Shape::PointerRead);
  }
  if (operationCode ==
          MachineOperation{MachineFamily::Ptr, MachineMethod::FromRef} ||
      operationCode ==
          MachineOperation{MachineFamily::Ptr, MachineMethod::FromMut}) {
    if (operands.size() != 1 || !types.isView(operands[0]) ||
        (operationCode ==
             MachineOperation{MachineFamily::Ptr, MachineMethod::FromMut} &&
         types.view(operands[0]).mode != ParameterMode::Mut))
      return std::nullopt;
    return signature(types.view(operands[0]).payload,
                     operationCode == MachineOperation{MachineFamily::Ptr,
                                                       MachineMethod::FromMut}
                         ? Shape::PointerMut
                         : Shape::PointerRead);
  }
  if ((operationCode.family == MachineFamily::Numeric)) {
    auto method = operation.substr(8);
    auto methodCode = operationCode.method;
    bool fromBytes = methodCode == MachineMethod::FromBeBytes ||
                     methodCode == MachineMethod::FromLeBytes ||
                     methodCode == MachineMethod::FromNeBytes;
    if (fromBytes) {
      if (operands.size() != 1 || !isNumeric(argument) ||
          !types.isProduct(operands[0]) ||
          types.product(operands[0]).kind != AggregateKind::Array ||
          types.product(operands[0]).components.empty() ||
          types.product(operands[0]).components[0] != Type::U8 ||
          types.arrayLength(operands[0]) !=
              std::optional<std::uint64_t>{
                  (isInteger(argument)
                       ? integerWidth(argument, types.targetPointerBits())
                   : argument == Type::F32 ? 32u
                                           : 64u) /
                  8u})
        return std::nullopt;
      return signature(argument);
    }
    if (operands.empty())
      return std::nullopt;
    bool makeAscii = methodCode == MachineMethod::MakeAsciiLowercase ||
                     methodCode == MachineMethod::MakeAsciiUppercase;
    auto self = operands[0];
    if (types.isView(self)) {
      if (!makeAscii || types.view(self).mode != ParameterMode::Mut ||
          types.view(self).payload != Type::U8)
        return std::nullopt;
      self = types.view(self).payload;
    } else if (!isNumeric(self))
      return std::nullopt;
    if (methodCode == MachineMethod::CheckedCast)
      return operands.size() == 1 && isInteger(argument)
                 ? signature(argument, Shape::Optional)
                 : std::nullopt;
    if (methodCode == MachineMethod::ToIntUnchecked)
      return operands.size() == 1 && isFloating(self) && isInteger(argument)
                 ? signature(argument, Shape::Value, true)
                 : std::nullopt;
    bool toBytes = methodCode == MachineMethod::ToBeBytes ||
                   methodCode == MachineMethod::ToLeBytes ||
                   methodCode == MachineMethod::ToNeBytes;
    if (argument != Type::Unknown && methodCode != MachineMethod::FromBits &&
        !toBytes && methodCode != MachineMethod::SinCos && self != argument)
      return std::nullopt;
    if (methodCode == MachineMethod::SinCos)
      return operands.size() == 1 && isFloating(self) &&
                     types.isProduct(argument) &&
                     types.product(argument).kind == AggregateKind::Tuple &&
                     types.product(argument).components ==
                         std::vector<Type>{self, self}
                 ? signature(argument)
                 : std::nullopt;
    if (methodCode == MachineMethod::ToBits) {
      if (operands.size() != 1 || !isFloating(self))
        return std::nullopt;
      return signature(self == Type::F32 ? Type::U32 : Type::U64);
    }
    if (methodCode == MachineMethod::FromBits) {
      if (operands.size() != 1 || !isFloating(argument) ||
          self != (argument == Type::F32 ? Type::U32 : Type::U64))
        return std::nullopt;
      return signature(argument);
    }
    if (methodCode == MachineMethod::ToBeBytes ||
        methodCode == MachineMethod::ToLeBytes ||
        methodCode == MachineMethod::ToNeBytes) {
      if (operands.size() != 1 || !types.isProduct(argument) ||
          types.product(argument).kind != AggregateKind::Array ||
          types.product(argument).components.empty() ||
          types.product(argument).components[0] != Type::U8)
        return std::nullopt;
      auto width = isInteger(self)
                       ? integerWidth(self, types.targetPointerBits())
                   : self == Type::F32 ? 32u
                                       : 64u;
      return types.arrayLength(argument) ==
                     std::optional<std::uint64_t>{width / 8u}
                 ? signature(argument)
                 : std::nullopt;
    }
    if (methodCode == MachineMethod::ToBe ||
        methodCode == MachineMethod::ToLe ||
        methodCode == MachineMethod::FromBe ||
        methodCode == MachineMethod::FromLe)
      return operands.size() == 1 && isInteger(self) ? signature(self)
                                                     : std::nullopt;
    if (isFloating(self)) {
      bool predicate = methodCode == MachineMethod::IsNan ||
                       methodCode == MachineMethod::IsInfinite ||
                       methodCode == MachineMethod::IsFinite ||
                       methodCode == MachineMethod::IsSignNegative ||
                       methodCode == MachineMethod::IsSignPositive ||
                       methodCode == MachineMethod::IsSubnormal ||
                       methodCode == MachineMethod::IsNormal;
      bool unary = predicate || methodCode == MachineMethod::Abs ||
                   methodCode == MachineMethod::Sqrt ||
                   methodCode == MachineMethod::Floor ||
                   methodCode == MachineMethod::Ceil ||
                   methodCode == MachineMethod::Trunc ||
                   methodCode == MachineMethod::Round ||
                   methodCode == MachineMethod::RoundTiesEven ||
                   methodCode == MachineMethod::Sin ||
                   methodCode == MachineMethod::Cos ||
                   methodCode == MachineMethod::Tan ||
                   methodCode == MachineMethod::Asin ||
                   methodCode == MachineMethod::Acos ||
                   methodCode == MachineMethod::Atan ||
                   methodCode == MachineMethod::Sinh ||
                   methodCode == MachineMethod::Cosh ||
                   methodCode == MachineMethod::Tanh ||
                   methodCode == MachineMethod::Asinh ||
                   methodCode == MachineMethod::Acosh ||
                   methodCode == MachineMethod::Atanh ||
                   methodCode == MachineMethod::Exp ||
                   methodCode == MachineMethod::Exp2 ||
                   methodCode == MachineMethod::ExpM1 ||
                   methodCode == MachineMethod::Ln ||
                   methodCode == MachineMethod::Ln1p ||
                   methodCode == MachineMethod::Log2 ||
                   methodCode == MachineMethod::Log10 ||
                   methodCode == MachineMethod::Cbrt ||
                   methodCode == MachineMethod::Fract ||
                   methodCode == MachineMethod::Recip ||
                   methodCode == MachineMethod::Signum ||
                   methodCode == MachineMethod::ToDegrees ||
                   methodCode == MachineMethod::ToRadians ||
                   methodCode == MachineMethod::NextUp ||
                   methodCode == MachineMethod::NextDown;
      bool clamp = methodCode == MachineMethod::Clamp;
      bool binary = methodCode == MachineMethod::Copysign ||
                    methodCode == MachineMethod::Atan2 ||
                    methodCode == MachineMethod::Log ||
                    methodCode == MachineMethod::Powf ||
                    methodCode == MachineMethod::Hypot ||
                    methodCode == MachineMethod::DivEuclid ||
                    methodCode == MachineMethod::RemEuclid ||
                    methodCode == MachineMethod::Midpoint ||
                    methodCode == MachineMethod::Min ||
                    methodCode == MachineMethod::Max;
      auto count = methodCode == MachineMethod::MulAdd ? 3u
                   : methodCode == MachineMethod::Powi ? 2u
                   : clamp                             ? 3u
                   : binary                            ? 2u
                                                       : 1u;
      bool powi = methodCode == MachineMethod::Powi;
      if ((!unary && count == 1) || operands.size() != count ||
          (powi ? operands[1] != Type::I32
                : !std::all_of(operands.begin(), operands.end(),
                               [&](Type type) { return type == self; })))
        return std::nullopt;
      return signature(predicate ? Type::Bool : self);
    }
    if (methodCode == MachineMethod::CountOnes ||
        methodCode == MachineMethod::CountZeros ||
        methodCode == MachineMethod::LeadingZeros ||
        methodCode == MachineMethod::TrailingZeros ||
        methodCode == MachineMethod::LeadingOnes ||
        methodCode == MachineMethod::TrailingOnes ||
        methodCode == MachineMethod::SwapBytes ||
        methodCode == MachineMethod::ReverseBits) {
      if (operands.size() != 1)
        return std::nullopt;
      return signature(methodCode == MachineMethod::SwapBytes ||
                               methodCode == MachineMethod::ReverseBits
                           ? self
                           : Type::U32);
    }
    if (methodCode == MachineMethod::RotateLeft ||
        methodCode == MachineMethod::RotateRight) {
      if (operands.size() != 2 || operands[1] != Type::U32)
        return std::nullopt;
      return signature(self);
    }
    if (!isInteger(self))
      return std::nullopt;
    auto unsignedType = [&] {
      if (self == Type::I8 || self == Type::U8)
        return Type::U8;
      if (self == Type::I16 || self == Type::U16)
        return Type::U16;
      if (self == Type::I32 || self == Type::U32)
        return Type::U32;
      if (self == Type::I64 || self == Type::U64)
        return Type::U64;
      if (self == Type::I128 || self == Type::U128)
        return Type::U128;
      return Type::Usize;
    };
    auto signedType = [&] {
      if (self == Type::I8 || self == Type::U8)
        return Type::I8;
      if (self == Type::I16 || self == Type::U16)
        return Type::I16;
      if (self == Type::I32 || self == Type::U32)
        return Type::I32;
      if (self == Type::I64 || self == Type::U64)
        return Type::I64;
      if (self == Type::I128 || self == Type::U128)
        return Type::I128;
      return Type::Isize;
    };
    if (methodCode == MachineMethod::IsPositive ||
        methodCode == MachineMethod::IsNegative ||
        methodCode == MachineMethod::Signum)
      return operands.size() == 1 && isSignedInteger(self)
                 ? signature(methodCode == MachineMethod::Signum ? self
                                                                 : Type::Bool)
                 : std::nullopt;
    if (methodCode == MachineMethod::IsPowerOfTwo)
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(Type::Bool)
                 : std::nullopt;
    if (methodCode == MachineMethod::BitWidth)
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(Type::U32)
                 : std::nullopt;
    if (methodCode == MachineMethod::HighestOne ||
        methodCode == MachineMethod::LowestOne)
      return operands.size() == 1 ? signature(Type::U32, Shape::Optional)
                                  : std::nullopt;
    if (methodCode == MachineMethod::IsolateHighestOne ||
        methodCode == MachineMethod::IsolateLowestOne)
      return operands.size() == 1 ? signature(self) : std::nullopt;
    if (methodCode == MachineMethod::CarryingAdd ||
        methodCode == MachineMethod::BorrowingSub)
      return operands.size() == 3 && !isSignedInteger(self) &&
                     operands[1] == self && operands[2] == Type::Bool
                 ? signature(self, Shape::Overflow)
                 : std::nullopt;
    if (methodCode == MachineMethod::CarryingMul ||
        methodCode == MachineMethod::CarryingMulAdd)
      return operands.size() ==
                         (methodCode == MachineMethod::CarryingMul ? 3u : 4u) &&
                     !isSignedInteger(self) &&
                     std::all_of(operands.begin(), operands.end(),
                                 [&](Type type) { return type == self; })
                 ? signature(self, Shape::Pair)
                 : std::nullopt;
    if (methodCode == MachineMethod::CheckedSignedDiff)
      return operands.size() == 2 && !isSignedInteger(self) &&
                     operands[1] == self
                 ? signature(signedType(), Shape::Optional)
                 : std::nullopt;
    if (methodCode == MachineMethod::Ilog2 ||
        methodCode == MachineMethod::Ilog10 ||
        methodCode == MachineMethod::CheckedIlog2 ||
        methodCode == MachineMethod::CheckedIlog10)
      return operands.size() == 1
                 ? signature(Type::U32, method.starts_with("checked_")
                                            ? Shape::Optional
                                            : Shape::Value)
                 : std::nullopt;
    if (methodCode == MachineMethod::Ilog ||
        methodCode == MachineMethod::CheckedIlog)
      return operands.size() == 2 && operands[1] == self
                 ? signature(Type::U32, method.starts_with("checked_")
                                            ? Shape::Optional
                                            : Shape::Value)
                 : std::nullopt;
    if (methodCode == MachineMethod::Isqrt ||
        methodCode == MachineMethod::CheckedIsqrt)
      return operands.size() == 1
                 ? signature(self, method.starts_with("checked_")
                                       ? Shape::Optional
                                       : Shape::Value)
                 : std::nullopt;
    if (methodCode == MachineMethod::NextPowerOfTwo ||
        methodCode == MachineMethod::CheckedNextPowerOfTwo)
      return operands.size() == 1 && !isSignedInteger(self)
                 ? signature(self, method.starts_with("checked_")
                                       ? Shape::Optional
                                       : Shape::Value)
                 : std::nullopt;
    if (methodCode == MachineMethod::DivCeil ||
        methodCode == MachineMethod::NextMultipleOf ||
        methodCode == MachineMethod::CheckedNextMultipleOf ||
        methodCode == MachineMethod::IsMultipleOf)
      return operands.size() == 2 && operands[1] == self &&
                     !isSignedInteger(self)
                 ? signature(methodCode == MachineMethod::IsMultipleOf
                                 ? Type::Bool
                                 : self,
                             method.starts_with("checked_") ? Shape::Optional
                                                            : Shape::Value)
                 : std::nullopt;
    if (methodCode == MachineMethod::Midpoint)
      return operands.size() == 2 && operands[1] == self ? signature(self)
                                                         : std::nullopt;
    if (methodCode == MachineMethod::UnboundedShl ||
        methodCode == MachineMethod::UnboundedShr)
      return operands.size() == 2 && operands[1] == Type::U32 ? signature(self)
                                                              : std::nullopt;
    if (method.starts_with("unchecked_")) {
      auto unchecked = method.substr(10);
      bool unary = unchecked == "neg";
      bool shift = unchecked == "shl" || unchecked == "shr";
      if (unchecked != "add" && unchecked != "sub" && unchecked != "mul" &&
          !unary && !shift)
        return std::nullopt;
      return operands.size() == (unary ? 1u : 2u) &&
                     (unary || operands[1] == (shift ? Type::U32 : self))
                 ? signature(self, Shape::Value, true)
                 : std::nullopt;
    }
    if (methodCode == MachineMethod::CastSigned ||
        methodCode == MachineMethod::CastUnsigned)
      return operands.size() == 1 &&
                     ((methodCode == MachineMethod::CastSigned &&
                       !isSignedInteger(self)) ||
                      (methodCode == MachineMethod::CastUnsigned &&
                       isSignedInteger(self)))
                 ? signature(methodCode == MachineMethod::CastSigned
                                 ? signedType()
                                 : unsignedType())
                 : std::nullopt;
    if (methodCode == MachineMethod::IsAscii ||
        methodCode == MachineMethod::IsAsciiAlphabetic ||
        methodCode == MachineMethod::IsAsciiAlphanumeric ||
        methodCode == MachineMethod::IsAsciiControl ||
        methodCode == MachineMethod::IsAsciiDigit ||
        methodCode == MachineMethod::IsAsciiGraphic ||
        methodCode == MachineMethod::IsAsciiHexdigit ||
        methodCode == MachineMethod::IsAsciiLowercase ||
        methodCode == MachineMethod::IsAsciiPunctuation ||
        methodCode == MachineMethod::IsAsciiUppercase ||
        methodCode == MachineMethod::IsAsciiWhitespace)
      return self == Type::U8 && operands.size() == 1 ? signature(Type::Bool)
                                                      : std::nullopt;
    if (methodCode == MachineMethod::ToAsciiLowercase ||
        methodCode == MachineMethod::ToAsciiUppercase)
      return self == Type::U8 && operands.size() == 1 ? signature(Type::U8)
                                                      : std::nullopt;
    if (makeAscii)
      return self == Type::U8 && operands.size() == 1 &&
                     types.isView(operands[0]) &&
                     types.view(operands[0]).mode == ParameterMode::Mut
                 ? signature(Type::Unit)
                 : std::nullopt;
    if (methodCode == MachineMethod::EqIgnoreAsciiCase)
      return self == Type::U8 && operands.size() == 2 && operands[1] == Type::U8
                 ? signature(Type::Bool)
                 : std::nullopt;
    if (methodCode == MachineMethod::UnsignedAbs)
      return operands.size() == 1 && isSignedInteger(self)
                 ? signature(unsignedType())
                 : std::nullopt;
    if (methodCode == MachineMethod::AbsDiff)
      return operands.size() == 2 && operands[1] == self
                 ? signature(unsignedType())
                 : std::nullopt;
    if (methodCode == MachineMethod::Pow ||
        methodCode == MachineMethod::CheckedPow ||
        methodCode == MachineMethod::WrappingPow ||
        methodCode == MachineMethod::OverflowingPow ||
        methodCode == MachineMethod::SaturatingPow ||
        methodCode == MachineMethod::StrictPow) {
      auto shape = methodCode == MachineMethod::CheckedPow ? Shape::Optional
                   : methodCode == MachineMethod::OverflowingPow
                       ? Shape::Overflow
                       : Shape::Value;
      return operands.size() == 2 && operands[1] == Type::U32
                 ? signature(self, shape)
                 : std::nullopt;
    }
    bool strict = method.starts_with("strict_");
    if (strict) {
      method.remove_prefix(7);
      if (method.starts_with("checked_") || method.starts_with("wrapping_") ||
          method.starts_with("overflowing_") ||
          method.starts_with("saturating_"))
        return std::nullopt;
    }
    Shape shape = Shape::Value;
    if (method.starts_with("wrapping_"))
      method.remove_prefix(9);
    else if (method.starts_with("checked_")) {
      method.remove_prefix(8);
      shape = Shape::Optional;
    } else if (method.starts_with("overflowing_")) {
      method.remove_prefix(12);
      shape = Shape::Overflow;
    } else if (method.starts_with("saturating_"))
      method.remove_prefix(11);
    else if (!strict && !method.ends_with("_signed") &&
             !method.ends_with("_unsigned") &&
             methodCode != MachineMethod::DivEuclid &&
             methodCode != MachineMethod::RemEuclid &&
             methodCode != MachineMethod::Abs)
      return std::nullopt;
    methodCode = machineMethod(method);
    bool mixedSigned = method.ends_with("_signed");
    bool mixedUnsigned = method.ends_with("_unsigned");
    if (mixedSigned || mixedUnsigned) {
      method.remove_suffix(mixedSigned ? 7 : 9);
      methodCode = machineMethod(method);
      bool validOperation =
          methodCode == MachineMethod::Add || methodCode == MachineMethod::Sub;
      bool validSign =
          mixedSigned ? !isSignedInteger(self) : isSignedInteger(self);
      auto expected = mixedSigned ? signedType() : unsignedType();
      return validOperation && validSign && operands.size() == 2 &&
                     operands[1] == expected
                 ? signature(self, shape)
                 : std::nullopt;
    }
    bool unary =
        methodCode == MachineMethod::Neg || methodCode == MachineMethod::Abs;
    bool shift =
        methodCode == MachineMethod::Shl || methodCode == MachineMethod::Shr;
    if (methodCode != MachineMethod::Add && methodCode != MachineMethod::Sub &&
        methodCode != MachineMethod::Mul && methodCode != MachineMethod::Div &&
        methodCode != MachineMethod::Rem && !unary && !shift &&
        methodCode != MachineMethod::DivEuclid &&
        methodCode != MachineMethod::RemEuclid)
      return std::nullopt;
    if (methodCode == MachineMethod::Abs && !isSignedInteger(self))
      return std::nullopt;
    if (operands.size() != (unary ? 1u : 2u) ||
        (!unary && operands[1] != (shift ? Type::U32 : self)))
      return std::nullopt;
    if (operation.starts_with("numeric.saturating_") &&
        (shift || methodCode == MachineMethod::Rem))
      return std::nullopt;
    if (operation.starts_with("numeric.saturating_") &&
        (methodCode == MachineMethod::DivEuclid ||
         methodCode == MachineMethod::RemEuclid))
      return std::nullopt;
    return signature(self, shape);
  }
  if (!(operationCode.family == MachineFamily::Ptr) || operands.empty() ||
      !types.isPointer(operands[0]))
    return std::nullopt;
  auto pointer = operands[0];
  auto descriptor = types.pointer(pointer);
  auto method = operation.substr(4);
  auto methodCode = operationCode.method;
  if (methodCode == MachineMethod::AsArray ||
      methodCode == MachineMethod::AsMutArray) {
    if (operands.size() != 1 || !types.isSlice(descriptor.payload) ||
        !types.isPointer(argument))
      return std::nullopt;
    auto target = types.pointer(argument);
    bool exclusive = methodCode == MachineMethod::AsMutArray;
    if (target.mode != (exclusive ? ParameterMode::Mut : ParameterMode::Read) ||
        (exclusive && descriptor.mode != ParameterMode::Mut) ||
        !types.isProduct(target.payload))
      return std::nullopt;
    const auto &array = types.product(target.payload);
    if (array.kind != AggregateKind::Array || array.components.size() != 1 ||
        array.components[0] != types.slice(descriptor.payload).element)
      return std::nullopt;
    return signature(argument, Shape::Optional);
  }
  if (methodCode == MachineMethod::AsRef ||
      methodCode == MachineMethod::AsMut ||
      methodCode == MachineMethod::AsRefUnchecked ||
      methodCode == MachineMethod::AsMutUnchecked) {
    bool exclusive = methodCode == MachineMethod::AsMut ||
                     methodCode == MachineMethod::AsMutUnchecked;
    if (operands.size() != 1 || !types.isView(argument) ||
        types.view(argument).payload != descriptor.payload ||
        types.view(argument).mode !=
            (exclusive ? ParameterMode::Mut : ParameterMode::Read) ||
        (exclusive && descriptor.mode != ParameterMode::Mut))
      return std::nullopt;
    return signature(
        argument,
        method.ends_with("_unchecked") ? Shape::Value : Shape::Optional, true);
  }
  if (methodCode == MachineMethod::Copy ||
      methodCode == MachineMethod::CopyNonoverlapping ||
      methodCode == MachineMethod::Swap ||
      methodCode == MachineMethod::SwapNonoverlapping) {
    bool swap = method.starts_with("swap");
    auto count = methodCode == MachineMethod::Swap ? 2u : 3u;
    return operands.size() == count && types.isSized(descriptor.payload) &&
                   (!swap || descriptor.mode == ParameterMode::Mut) &&
                   types.isPointer(operands[1]) &&
                   types.pointer(operands[1]).mode == ParameterMode::Mut &&
                   types.pointer(operands[1]).payload == descriptor.payload &&
                   (count == 2 || operands[2] == Type::Usize)
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  }
  if (methodCode == MachineMethod::WriteBytes)
    return operands.size() == 3 && descriptor.mode == ParameterMode::Mut &&
                   types.isSized(descriptor.payload) &&
                   operands[1] == Type::U8 && operands[2] == Type::Usize
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  if (methodCode == MachineMethod::Replace)
    return operands.size() == 2 && descriptor.mode == ParameterMode::Mut &&
                   types.isSized(descriptor.payload) &&
                   operands[1] == descriptor.payload
               ? signature(descriptor.payload, Shape::Value, true)
               : std::nullopt;
  if (methodCode == MachineMethod::OffsetFrom ||
      methodCode == MachineMethod::OffsetFromUnsigned ||
      methodCode == MachineMethod::ByteOffsetFrom ||
      methodCode == MachineMethod::ByteOffsetFromUnsigned)
    return operands.size() == 2 && types.isPointer(operands[1]) &&
                   types.pointer(operands[1]).payload == descriptor.payload &&
                   (method.starts_with("byte_") ||
                    types.isSized(descriptor.payload))
               ? signature(method.ends_with("_unsigned") ? Type::Usize
                                                         : Type::Isize,
                           Shape::Value, true)
               : std::nullopt;
  if (methodCode == MachineMethod::DropInPlace)
    return operands.size() == 1 && descriptor.mode == ParameterMode::Mut &&
                   (types.isSized(descriptor.payload) ||
                    (types.isParameter(descriptor.payload) &&
                     !types.isSized(descriptor.payload)) ||
                    (types.isSlice(descriptor.payload) &&
                     types.isSized(types.slice(descriptor.payload).element)) ||
                    types.isErased(descriptor.payload))
               ? signature(Type::Unit, Shape::Value, true)
               : std::nullopt;
  if (methodCode == MachineMethod::IsNull ||
      methodCode == MachineMethod::Addr ||
      methodCode == MachineMethod::ExposeProvenance) {
    if (operands.size() != 1)
      return std::nullopt;
    return signature(methodCode == MachineMethod::IsNull ? Type::Bool
                                                         : Type::Usize);
  }
  if (methodCode == MachineMethod::Cast ||
      methodCode == MachineMethod::CastMut ||
      methodCode == MachineMethod::CastConst) {
    if (operands.size() != 1 ||
        (methodCode == MachineMethod::Cast && !types.isSized(argument)))
      return std::nullopt;
    return signature(methodCode == MachineMethod::Cast ? argument
                                                       : descriptor.payload,
                     methodCode == MachineMethod::CastMut ||
                             (methodCode == MachineMethod::Cast &&
                              descriptor.mode == ParameterMode::Mut)
                         ? Shape::PointerMut
                         : Shape::PointerRead);
  }
  if (methodCode == MachineMethod::WithAddr) {
    if (operands.size() != 2 || operands[1] != Type::Usize)
      return std::nullopt;
    return signature(pointer);
  }
  if (methodCode == MachineMethod::Read ||
      methodCode == MachineMethod::ReadVolatile ||
      methodCode == MachineMethod::ReadUnaligned) {
    if (operands.size() != 1 || !types.isSized(descriptor.payload))
      return std::nullopt;
    return signature(descriptor.payload, Shape::Value, true);
  }
  if (methodCode == MachineMethod::Write ||
      methodCode == MachineMethod::WriteVolatile ||
      methodCode == MachineMethod::WriteUnaligned) {
    if (operands.size() != 2 || descriptor.mode != ParameterMode::Mut ||
        operands[1] != descriptor.payload || !types.isSized(descriptor.payload))
      return std::nullopt;
    return signature(Type::Unit, Shape::Value, true);
  }
  bool wrapping = method.starts_with("wrapping_");
  if (wrapping)
    method.remove_prefix(9);
  bool bytes = method.starts_with("byte_");
  if (bytes)
    method.remove_prefix(5);
  methodCode = machineMethod(method);
  if (methodCode != MachineMethod::Add && methodCode != MachineMethod::Sub &&
      methodCode != MachineMethod::Offset)
    return std::nullopt;
  if (operands.size() != 2 || (!bytes && !types.isSized(descriptor.payload)) ||
      operands[1] !=
          (methodCode == MachineMethod::Offset ? Type::Isize : Type::Usize))
    return std::nullopt;
  return signature(pointer, Shape::Value, !wrapping);
}
bool machineResultMatches(const TypeStore &types,
                          const MachineSignature &signature, Type result) {
  using Shape = MachineSignature::Shape;
  if (signature.shape == Shape::RefProjection ||
      signature.shape == Shape::RefMutProjection) {
    if (!types.isProduct(result) ||
        types.product(result).kind != (signature.shape == Shape::RefProjection
                                           ? AggregateKind::Ref
                                           : AggregateKind::RefMut))
      return false;
    auto source = types.product(result).components[0];
    return types.isView(source) &&
           types.view(source).mode == ParameterMode::Read &&
           types.isProduct(types.view(source).payload) &&
           types.product(types.view(source).payload).kind ==
               AggregateKind::RefCell &&
           types.product(types.view(source).payload).components ==
               std::vector<Type>{signature.value};
  }
  if (signature.shape == Shape::UnguardedRef) {
    if (!types.isProduct(result) ||
        types.product(result).kind != AggregateKind::Outcome)
      return false;
    auto value = types.product(result).components[0];
    auto error = types.product(result).components[1];
    return types.isView(value) &&
           types.view(value).mode == ParameterMode::Read &&
           types.view(value).payload == signature.value &&
           types.isProduct(error) &&
           types.product(error).kind == AggregateKind::BorrowError;
  }
  if (signature.shape == Shape::Ref || signature.shape == Shape::RefMut ||
      signature.shape == Shape::TryRef || signature.shape == Shape::TryRefMut) {
    bool exclusive =
        signature.shape == Shape::RefMut || signature.shape == Shape::TryRefMut;
    bool fallible =
        signature.shape == Shape::TryRef || signature.shape == Shape::TryRefMut;
    if (fallible) {
      if (!types.isProduct(result) ||
          types.product(result).kind != AggregateKind::Outcome ||
          !types.isProduct(types.product(result).components[1]) ||
          types.product(types.product(result).components[1]).kind !=
              (exclusive ? AggregateKind::BorrowMutError
                         : AggregateKind::BorrowError))
        return false;
      result = types.product(result).components[0];
    }
    return types.isProduct(result) &&
           types.product(result).kind ==
               (exclusive ? AggregateKind::RefMut : AggregateKind::Ref) &&
           types.isView(types.product(result).components[0]) &&
           types.view(types.product(result).components[0]).mode ==
               ParameterMode::Read &&
           types.view(types.product(result).components[0]).payload ==
               signature.value;
  }
  if (signature.shape == Shape::Outcome)
    return types.isProduct(result) &&
           types.product(result).kind == AggregateKind::Outcome &&
           types.product(result).components ==
               std::vector<Type>{signature.value, signature.value};
  if (signature.shape == Shape::PinRead || signature.shape == Shape::PinMut)
    return types.isProduct(result) &&
           types.product(result).kind == AggregateKind::Pin &&
           types.isView(types.product(result).components[0]) &&
           types.view(types.product(result).components[0]).payload ==
               signature.value &&
           types.view(types.product(result).components[0]).mode ==
               (signature.shape == Shape::PinMut ? ParameterMode::Mut
                                                 : ParameterMode::Read);
  if (signature.shape == Shape::Value)
    return result == signature.value;
  if (signature.shape == Shape::PointerRead ||
      signature.shape == Shape::PointerMut)
    return types.isPointer(result) &&
           types.pointer(result).payload == signature.value &&
           types.pointer(result).mode == (signature.shape == Shape::PointerMut
                                              ? ParameterMode::Mut
                                              : ParameterMode::Read);
  if (signature.shape == Shape::ViewReadStatic)
    return types.isView(result) &&
           types.view(result).mode == ParameterMode::Read &&
           (types.view(result).region == RegionId::Static ||
            types.view(result).region == RegionId::Unspecified) &&
           types.view(result).payload == signature.value;
  if (signature.shape == Shape::ViewRead || signature.shape == Shape::ViewMut)
    return types.isView(result) &&
           types.view(result).payload == signature.value &&
           types.view(result).mode == (signature.shape == Shape::ViewMut
                                           ? ParameterMode::Mut
                                           : ParameterMode::Read);
  if (!types.isProduct(result))
    return false;
  const auto &record = types.product(result);
  if (signature.shape == Shape::Optional)
    return record.kind == AggregateKind::Optional &&
           record.components == std::vector<Type>{signature.value};
  return record.kind == AggregateKind::Tuple &&
         record.components ==
             std::vector<Type>{signature.value, signature.shape == Shape::Pair
                                                    ? signature.value
                                                    : Type::Bool};
}
} // namespace mettle
