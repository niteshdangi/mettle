import core.float.{FpCategory}

fn near_f32(value: f32, expected: f32, tolerance: f32): bool {
    (value - expected).abs() < tolerance
}

fn near_f64(value: f64, expected: f64, tolerance: f64): bool {
    (value - expected).abs() < tolerance
}

const F32_ABS: f32 = (-1.5f32).abs()
const F64_ABS: f64 = f64.from_bits(0x8000000000000000u64).abs()
const F32_ALGEBRAIC_ADD: f32 = 5.0f32.algebraic_add(2.0f32)
const F64_ALGEBRAIC_ADD: f64 = 5.0f64.algebraic_add(2.0f64)
const F32_ALGEBRAIC_SUB: f32 = 5.0f32.algebraic_sub(2.0f32)
const F64_ALGEBRAIC_SUB: f64 = 5.0f64.algebraic_sub(2.0f64)
const F32_ALGEBRAIC_MUL: f32 = 5.0f32.algebraic_mul(2.0f32)
const F64_ALGEBRAIC_MUL: f64 = 5.0f64.algebraic_mul(2.0f64)
const F32_ALGEBRAIC_DIV: f32 = 5.0f32.algebraic_div(2.0f32)
const F64_ALGEBRAIC_DIV: f64 = 5.0f64.algebraic_div(2.0f64)
const F32_ALGEBRAIC_REM: f32 = 5.0f32.algebraic_rem(2.0f32)
const F64_ALGEBRAIC_REM: f64 = 5.0f64.algebraic_rem(2.0f64)
const F32_CEIL: f32 = 1.25f32.ceil()
const F64_CEIL: f64 = (-1.25f64).ceil()
const F32_CLAMP: f32 = 5.0f32.clamp(0.0f32, 3.0f32)
const F64_CLAMP: f64 = (-5.0f64).clamp(-3.0f64, 0.0f64)
const F32_CLASSIFY: FpCategory = 1.0f32.classify()
const F64_CLASSIFY: FpCategory = f64.from_bits(1u64).classify()
const F32_COPYSIGN: f32 = 2.0f32.copysign(-1.0f32)
const F64_COPYSIGN: f64 = (-2.0f64).copysign(1.0f64)
const F32_FLOOR: f32 = (-1.25f32).floor()
const F64_FLOOR: f64 = 1.25f64.floor()
const F32_FRACT: f32 = (-1.25f32).fract()
const F64_FRACT: f64 = 2.25f64.fract()
const F32_FROM_BE_BYTES: f32 = f32.from_be_bytes([0x3fu8, 0x80u8, 0u8, 0u8])
const F64_FROM_BE_BYTES: f64 = f64.from_be_bytes([0x3fu8, 0xf0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8])
const F32_FROM_BITS: f32 = f32.from_bits(0x3fc00000u32)
const F64_FROM_BITS: f64 = f64.from_bits(0x3ff8000000000000u64)
const F32_FROM_LE_BYTES: f32 = f32.from_le_bytes([0u8, 0u8, 0x80u8, 0x3fu8])
const F64_FROM_LE_BYTES: f64 = f64.from_le_bytes([0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0xf0u8, 0x3fu8])
const F32_FROM_NE_BYTES: f32 = f32.from_ne_bytes(1.0f32.to_ne_bytes())
const F64_FROM_NE_BYTES: f64 = f64.from_ne_bytes(1.0f64.to_ne_bytes())
const F32_IS_FINITE: bool = 1.0f32.is_finite()
const F64_IS_FINITE: bool = 1.0f64.is_finite()
const F32_IS_INFINITE: bool = f32.from_bits(0x7f800000u32).is_infinite()
const F64_IS_INFINITE: bool = f64.from_bits(0x7ff0000000000000u64).is_infinite()
const F32_IS_NAN: bool = f32.from_bits(0x7fc00000u32).is_nan()
const F64_IS_NAN: bool = f64.from_bits(0x7ff8000000000000u64).is_nan()
const F32_IS_NORMAL: bool = 1.0f32.is_normal()
const F64_IS_NORMAL: bool = 1.0f64.is_normal()
const F32_IS_SIGN_NEGATIVE: bool = f32.from_bits(0x80000000u32).is_sign_negative()
const F64_IS_SIGN_NEGATIVE: bool = f64.from_bits(0x8000000000000000u64).is_sign_negative()
const F32_IS_SIGN_POSITIVE: bool = 0.0f32.is_sign_positive()
const F64_IS_SIGN_POSITIVE: bool = 0.0f64.is_sign_positive()
const F32_IS_SUBNORMAL: bool = f32.from_bits(1u32).is_subnormal()
const F64_IS_SUBNORMAL: bool = f64.from_bits(1u64).is_subnormal()
const F32_MAX_OF_ZERO: f32 = 0.0f32.max(f32.from_bits(0x80000000u32))
const F64_MAX: f64 = 2.0f64.max(3.0f64)
const F32_MIDPOINT: f32 = 2.0f32.midpoint(4.0f32)
const F64_MIDPOINT: f64 = 2.0f64.midpoint(4.0f64)
const F32_MIDPOINT_MAX: f32 = f32.from_bits(0x7f7fffffu32).midpoint(f32.from_bits(0x7f7fffffu32))
const F64_MIDPOINT_MAX: f64 = f64.from_bits(0x7fefffffffffffffu64).midpoint(f64.from_bits(0x7fefffffffffffffu64))
const F32_MIN_OF_ZERO: f32 = 0.0f32.min(f32.from_bits(0x80000000u32))
const F64_MIN: f64 = 2.0f64.min(3.0f64)
const F32_MUL_ADD: f32 = f32.from_bits(0x3f800001u32).mul_add(f32.from_bits(0x3f7ffffeu32), -1.0f32)
const F64_MUL_ADD: f64 = f64.from_bits(0x3ff0000000000001u64).mul_add(f64.from_bits(0x3feffffffffffffeu64), -1.0f64)
const F32_NEXT_DOWN: f32 = 0.0f32.next_down()
const F64_NEXT_DOWN: f64 = 0.0f64.next_down()
const F32_NEXT_UP: f32 = 0.0f32.next_up()
const F64_NEXT_UP: f64 = 0.0f64.next_up()
const F32_RECIP: f32 = 4.0f32.recip()
const F64_RECIP: f64 = 4.0f64.recip()
const F32_ROUND: f32 = 2.5f32.round()
const F64_ROUND: f64 = (-2.5f64).round()
const F32_ROUND_TIES_EVEN: f32 = 2.5f32.round_ties_even()
const F64_ROUND_TIES_EVEN: f64 = 3.5f64.round_ties_even()
const F32_SIGNUM: f32 = (-2.0f32).signum()
const F64_SIGNUM: f64 = 2.0f64.signum()
const F32_TO_BE_BYTES: [u8; 4] = 1.0f32.to_be_bytes()
const F64_TO_BE_BYTES: [u8; 8] = 1.0f64.to_be_bytes()
const F32_TO_BITS: u32 = 1.5f32.to_bits()
const F64_TO_BITS: u64 = 1.5f64.to_bits()
const F32_TO_DEGREES: f32 = 3.1415927f32.to_degrees()
const F64_TO_DEGREES: f64 = 3.141592653589793f64.to_degrees()
const F32_TO_LE_BYTES: [u8; 4] = 1.0f32.to_le_bytes()
const F64_TO_LE_BYTES: [u8; 8] = 1.0f64.to_le_bytes()
const F32_TO_NE_BYTES: [u8; 4] = 1.0f32.to_ne_bytes()
const F64_TO_NE_BYTES: [u8; 8] = 1.0f64.to_ne_bytes()
const F32_TO_RADIANS: f32 = 180.0f32.to_radians()
const F64_TO_RADIANS: f64 = 180.0f64.to_radians()
const F32_TRUNC: f32 = (-1.75f32).trunc()
const F64_TRUNC: f64 = 1.75f64.trunc()

const fn float_const_frame_f32(value: f32): f32 {
    f32.from_bits(value.to_bits())
}

const fn float_const_frame_f64(value: f64): f64 {
    f64.from_bits(value.to_bits())
}

const F32_QNAN_BITS: u32 = f32.from_bits(0x7fc12345u32).to_bits()
const F32_SNAN_BITS: u32 = f32.from_bits(0xff812345u32).to_bits()
const F64_QNAN_BITS: u64 = f64.from_bits(0x7ff8123456789abcu64).to_bits()
const F64_SNAN_BITS: u64 = f64.from_bits(0xfff0123456789abcu64).to_bits()
const F32_QNAN_BE_BITS: u32 = f32.from_be_bytes(f32.from_bits(0x7fc12345u32).to_be_bytes()).to_bits()
const F32_QNAN_LE_BITS: u32 = f32.from_le_bytes(f32.from_bits(0x7fc12345u32).to_le_bytes()).to_bits()
const F32_QNAN_NE_BITS: u32 = f32.from_ne_bytes(f32.from_bits(0x7fc12345u32).to_ne_bytes()).to_bits()
const F32_SNAN_BE_BITS: u32 = f32.from_be_bytes(f32.from_bits(0xff812345u32).to_be_bytes()).to_bits()
const F32_SNAN_LE_BITS: u32 = f32.from_le_bytes(f32.from_bits(0xff812345u32).to_le_bytes()).to_bits()
const F32_SNAN_NE_BITS: u32 = f32.from_ne_bytes(f32.from_bits(0xff812345u32).to_ne_bytes()).to_bits()
const F64_QNAN_BE_BITS: u64 = f64.from_be_bytes(f64.from_bits(0x7ff8123456789abcu64).to_be_bytes()).to_bits()
const F64_QNAN_LE_BITS: u64 = f64.from_le_bytes(f64.from_bits(0x7ff8123456789abcu64).to_le_bytes()).to_bits()
const F64_QNAN_NE_BITS: u64 = f64.from_ne_bytes(f64.from_bits(0x7ff8123456789abcu64).to_ne_bytes()).to_bits()
const F64_SNAN_BE_BITS: u64 = f64.from_be_bytes(f64.from_bits(0xfff0123456789abcu64).to_be_bytes()).to_bits()
const F64_SNAN_LE_BITS: u64 = f64.from_le_bytes(f64.from_bits(0xfff0123456789abcu64).to_le_bytes()).to_bits()
const F64_SNAN_NE_BITS: u64 = f64.from_ne_bytes(f64.from_bits(0xfff0123456789abcu64).to_ne_bytes()).to_bits()
const F32_NEG_ZERO_BITS: u32 = f32.from_bits(0x80000000u32).to_bits()
const F32_NEG_ZERO_BE_BITS: u32 = f32.from_be_bytes(f32.from_bits(0x80000000u32).to_be_bytes()).to_bits()
const F32_NEG_ZERO_LE_BITS: u32 = f32.from_le_bytes(f32.from_bits(0x80000000u32).to_le_bytes()).to_bits()
const F32_NEG_ZERO_NE_BITS: u32 = f32.from_ne_bytes(f32.from_bits(0x80000000u32).to_ne_bytes()).to_bits()
const F64_NEG_ZERO_BITS: u64 = f64.from_bits(0x8000000000000000u64).to_bits()
const F64_NEG_ZERO_BE_BITS: u64 = f64.from_be_bytes(f64.from_bits(0x8000000000000000u64).to_be_bytes()).to_bits()
const F64_NEG_ZERO_LE_BITS: u64 = f64.from_le_bytes(f64.from_bits(0x8000000000000000u64).to_le_bytes()).to_bits()
const F64_NEG_ZERO_NE_BITS: u64 = f64.from_ne_bytes(f64.from_bits(0x8000000000000000u64).to_ne_bytes()).to_bits()
const F32_NEG_ZERO_BE_BYTES: [u8; 4] = f32.from_bits(0x80000000u32).to_be_bytes()
const F32_NEG_ZERO_LE_BYTES: [u8; 4] = f32.from_bits(0x80000000u32).to_le_bytes()
const F64_NEG_ZERO_BE_BYTES: [u8; 8] = f64.from_bits(0x8000000000000000u64).to_be_bytes()
const F64_NEG_ZERO_LE_BYTES: [u8; 8] = f64.from_bits(0x8000000000000000u64).to_le_bytes()
const F32_CONST_FRAME_BITS: u32 = float_const_frame_f32(f32.from_bits(0xff812345u32)).to_bits()
const F64_CONST_FRAME_BITS: u64 = float_const_frame_f64(f64.from_bits(0xfff0123456789abcu64)).to_bits()

fn main(): i32 {
    if F32_ABS != 1.5f32 || F64_ABS.to_bits() != 0u64 ||
       F32_ALGEBRAIC_ADD != 7.0f32 || F64_ALGEBRAIC_ADD != 7.0f64 ||
       F32_ALGEBRAIC_SUB != 3.0f32 || F64_ALGEBRAIC_SUB != 3.0f64 ||
       F32_ALGEBRAIC_MUL != 10.0f32 || F64_ALGEBRAIC_MUL != 10.0f64 ||
       F32_ALGEBRAIC_DIV != 2.5f32 || F64_ALGEBRAIC_DIV != 2.5f64 ||
       F32_ALGEBRAIC_REM != 1.0f32 || F64_ALGEBRAIC_REM != 1.0f64 {
        return 1
    }
    if F32_CEIL != 2.0f32 || F64_CEIL != -1.0f64 ||
       F32_CLAMP != 3.0f32 || F64_CLAMP != -3.0f64 ||
       F32_CLASSIFY != FpCategory.Normal || F64_CLASSIFY != FpCategory.Subnormal ||
       F32_COPYSIGN != -2.0f32 || F64_COPYSIGN != 2.0f64 ||
       F32_FLOOR != -2.0f32 || F64_FLOOR != 1.0f64 ||
       F32_FRACT.to_bits() != 0xbe800000u32 || F64_FRACT != 0.25f64 {
        return 2
    }
    if F32_FROM_BE_BYTES.to_bits() != 0x3f800000u32 ||
       F64_FROM_BE_BYTES.to_bits() != 0x3ff0000000000000u64 ||
       F32_FROM_BITS.to_bits() != 0x3fc00000u32 ||
       F64_FROM_BITS.to_bits() != 0x3ff8000000000000u64 ||
       F32_FROM_LE_BYTES.to_bits() != 0x3f800000u32 ||
       F64_FROM_LE_BYTES.to_bits() != 0x3ff0000000000000u64 ||
       F32_FROM_NE_BYTES.to_bits() != 0x3f800000u32 ||
       F64_FROM_NE_BYTES.to_bits() != 0x3ff0000000000000u64 {
        return 3
    }
    if !F32_IS_FINITE || !F64_IS_FINITE || !F32_IS_INFINITE ||
       !F64_IS_INFINITE || !F32_IS_NAN || !F64_IS_NAN ||
       !F32_IS_NORMAL || !F64_IS_NORMAL ||
       !F32_IS_SIGN_NEGATIVE || !F64_IS_SIGN_NEGATIVE ||
       !F32_IS_SIGN_POSITIVE || !F64_IS_SIGN_POSITIVE ||
       !F32_IS_SUBNORMAL || !F64_IS_SUBNORMAL {
        return 4
    }
    if F32_MAX_OF_ZERO.to_bits() != 0u32 || F64_MAX != 3.0f64 ||
       F32_MIDPOINT != 3.0f32 || F64_MIDPOINT != 3.0f64 ||
       F32_MIDPOINT_MAX.to_bits() != 0x7f7fffffu32 ||
       F64_MIDPOINT_MAX.to_bits() != 0x7fefffffffffffffu64 ||
       F32_MIN_OF_ZERO.to_bits() != 0x80000000u32 || F64_MIN != 2.0f64 ||
       F32_MUL_ADD.to_bits() != 0xa8800000u32 ||
       F64_MUL_ADD.to_bits() != 0xb970000000000000u64 ||
       F32_NEXT_DOWN.to_bits() != 0x80000001u32 ||
       F64_NEXT_DOWN.to_bits() != 0x8000000000000001u64 ||
       F32_NEXT_UP.to_bits() != 1u32 || F64_NEXT_UP.to_bits() != 1u64 {
        return 5
    }
    if F32_RECIP != 0.25f32 || F64_RECIP != 0.25f64 ||
       F32_ROUND != 3.0f32 || F64_ROUND != -3.0f64 ||
       F32_ROUND_TIES_EVEN != 2.0f32 || F64_ROUND_TIES_EVEN != 4.0f64 ||
       F32_SIGNUM != -1.0f32 || F64_SIGNUM != 1.0f64 ||
       F32_TRUNC != -1.0f32 || F64_TRUNC != 1.0f64 ||
       !near_f32(F32_TO_DEGREES, 180.0f32, 0.0001f32) ||
       !near_f64(F64_TO_DEGREES, 180.0f64, 0.0000000001f64) ||
       !near_f32(F32_TO_RADIANS, 3.1415927f32, 0.000001f32) ||
       !near_f64(F64_TO_RADIANS, 3.141592653589793f64, 0.000000000000001f64) {
        return 6
    }
    if F32_TO_BITS != 0x3fc00000u32 || F64_TO_BITS != 0x3ff8000000000000u64 ||
       F32_TO_BE_BYTES[0usize] != 0x3fu8 || F32_TO_BE_BYTES[1usize] != 0x80u8 ||
       F32_TO_BE_BYTES[2usize] != 0u8 || F32_TO_BE_BYTES[3usize] != 0u8 ||
       F64_TO_BE_BYTES[0usize] != 0x3fu8 || F64_TO_BE_BYTES[1usize] != 0xf0u8 ||
       F64_TO_BE_BYTES[2usize] != 0u8 || F64_TO_BE_BYTES[3usize] != 0u8 ||
       F64_TO_BE_BYTES[4usize] != 0u8 || F64_TO_BE_BYTES[5usize] != 0u8 ||
       F64_TO_BE_BYTES[6usize] != 0u8 || F64_TO_BE_BYTES[7usize] != 0u8 {
        return 7
    }
    if F32_TO_LE_BYTES[0usize] != 0u8 || F32_TO_LE_BYTES[1usize] != 0u8 ||
       F32_TO_LE_BYTES[2usize] != 0x80u8 || F32_TO_LE_BYTES[3usize] != 0x3fu8 ||
       F64_TO_LE_BYTES[0usize] != 0u8 || F64_TO_LE_BYTES[1usize] != 0u8 ||
       F64_TO_LE_BYTES[2usize] != 0u8 || F64_TO_LE_BYTES[3usize] != 0u8 ||
       F64_TO_LE_BYTES[4usize] != 0u8 || F64_TO_LE_BYTES[5usize] != 0u8 ||
       F64_TO_LE_BYTES[6usize] != 0xf0u8 || F64_TO_LE_BYTES[7usize] != 0x3fu8 ||
       f32.from_ne_bytes(F32_TO_NE_BYTES).to_bits() != 0x3f800000u32 ||
       f64.from_ne_bytes(F64_TO_NE_BYTES).to_bits() != 0x3ff0000000000000u64 {
        return 8
    }

    let inferredF32 = f32.from_bits(0x3fc00000u32)
    let inferredF64 = f64.from_bits(0x3ff8000000000000u64)
    let inferredF32Bits = inferredF32.to_bits()
    let inferredF64Bits = inferredF64.to_bits()
    let inferredF32Bytes = inferredF32.to_be_bytes()
    let inferredF64Bytes = inferredF64.to_be_bytes()
    if inferredF32Bits != 0x3fc00000u32 ||
       inferredF64Bits != 0x3ff8000000000000u64 ||
       inferredF32Bytes[0usize] != 0x3fu8 ||
       inferredF64Bytes[0usize] != 0x3fu8 {
        return 9
    }
    if F32_QNAN_BITS != 0x7fc12345u32 || F32_SNAN_BITS != 0xff812345u32 ||
       F64_QNAN_BITS != 0x7ff8123456789abcu64 ||
       F64_SNAN_BITS != 0xfff0123456789abcu64 {
        return 10
    }
    if F32_QNAN_BE_BITS != 0x7fc12345u32 || F32_QNAN_LE_BITS != 0x7fc12345u32 ||
       F32_QNAN_NE_BITS != 0x7fc12345u32 ||
       F32_SNAN_BE_BITS != 0xff812345u32 || F32_SNAN_LE_BITS != 0xff812345u32 ||
       F32_SNAN_NE_BITS != 0xff812345u32 ||
       F64_QNAN_BE_BITS != 0x7ff8123456789abcu64 ||
       F64_QNAN_LE_BITS != 0x7ff8123456789abcu64 ||
       F64_QNAN_NE_BITS != 0x7ff8123456789abcu64 ||
       F64_SNAN_BE_BITS != 0xfff0123456789abcu64 ||
       F64_SNAN_LE_BITS != 0xfff0123456789abcu64 ||
       F64_SNAN_NE_BITS != 0xfff0123456789abcu64 {
        return 11
    }
    if F32_NEG_ZERO_BITS != 0x80000000u32 ||
       F32_NEG_ZERO_BE_BITS != 0x80000000u32 ||
       F32_NEG_ZERO_LE_BITS != 0x80000000u32 ||
       F32_NEG_ZERO_NE_BITS != 0x80000000u32 ||
       F64_NEG_ZERO_BITS != 0x8000000000000000u64 ||
       F64_NEG_ZERO_BE_BITS != 0x8000000000000000u64 ||
       F64_NEG_ZERO_LE_BITS != 0x8000000000000000u64 ||
       F64_NEG_ZERO_NE_BITS != 0x8000000000000000u64 {
        return 12
    }
    if F32_NEG_ZERO_BE_BYTES[0usize] != 0x80u8 ||
       F32_NEG_ZERO_BE_BYTES[1usize] != 0u8 ||
       F32_NEG_ZERO_BE_BYTES[2usize] != 0u8 ||
       F32_NEG_ZERO_BE_BYTES[3usize] != 0u8 ||
       F32_NEG_ZERO_LE_BYTES[0usize] != 0u8 ||
       F32_NEG_ZERO_LE_BYTES[1usize] != 0u8 ||
       F32_NEG_ZERO_LE_BYTES[2usize] != 0u8 ||
       F32_NEG_ZERO_LE_BYTES[3usize] != 0x80u8 ||
       F64_NEG_ZERO_BE_BYTES[0usize] != 0x80u8 ||
       F64_NEG_ZERO_BE_BYTES[1usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[2usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[3usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[4usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[5usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[6usize] != 0u8 ||
       F64_NEG_ZERO_BE_BYTES[7usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[0usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[1usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[2usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[3usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[4usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[5usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[6usize] != 0u8 ||
       F64_NEG_ZERO_LE_BYTES[7usize] != 0x80u8 {
        return 13
    }
    if F32_CONST_FRAME_BITS != 0xff812345u32 ||
       F64_CONST_FRAME_BITS != 0xfff0123456789abcu64 {
        return 14
    }
    0
}
