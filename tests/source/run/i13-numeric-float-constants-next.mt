const F32_DIGITS: u32 = f32.DIGITS
const F64_DIGITS: u32 = f64.DIGITS
const F32_EPSILON: f32 = f32.EPSILON
const F64_EPSILON: f64 = f64.EPSILON
const F32_INFINITY: f32 = f32.INFINITY
const F64_INFINITY: f64 = f64.INFINITY
const F32_MANTISSA_DIGITS: u32 = f32.MANTISSA_DIGITS
const F64_MANTISSA_DIGITS: u32 = f64.MANTISSA_DIGITS
const F32_MAX_10_EXP: i32 = f32.MAX_10_EXP
const F64_MAX_10_EXP: i32 = f64.MAX_10_EXP
const F32_MAX_EXP: i32 = f32.MAX_EXP
const F64_MAX_EXP: i32 = f64.MAX_EXP
const F32_MIN_10_EXP: i32 = f32.MIN_10_EXP
const F64_MIN_10_EXP: i32 = f64.MIN_10_EXP
const F32_MIN_EXP: i32 = f32.MIN_EXP
const F64_MIN_EXP: i32 = f64.MIN_EXP
const F32_MIN_POSITIVE: f32 = f32.MIN_POSITIVE
const F64_MIN_POSITIVE: f64 = f64.MIN_POSITIVE
const F32_NAN: f32 = f32.NAN
const F64_NAN: f64 = f64.NAN
const F32_NEG_INFINITY: f32 = f32.NEG_INFINITY
const F64_NEG_INFINITY: f64 = f64.NEG_INFINITY
const F32_RADIX: u32 = f32.RADIX
const F64_RADIX: u32 = f64.RADIX

fn main(): i32 {
    if F32_DIGITS != 6u32 || F64_DIGITS != 15u32 ||
       F32_MANTISSA_DIGITS != 24u32 || F64_MANTISSA_DIGITS != 53u32 ||
       F32_RADIX != 2u32 || F64_RADIX != 2u32 {
        return 1
    }
    if F32_MAX_10_EXP != 38i32 || F64_MAX_10_EXP != 308i32 ||
       F32_MAX_EXP != 128i32 || F64_MAX_EXP != 1024i32 ||
       F32_MIN_10_EXP != -37i32 || F64_MIN_10_EXP != -307i32 ||
       F32_MIN_EXP != -125i32 || F64_MIN_EXP != -1021i32 {
        return 2
    }
    if F32_EPSILON.to_bits() != 0x34000000u32 ||
       F64_EPSILON.to_bits() != 0x3cb0000000000000u64 ||
       F32_MIN_POSITIVE.to_bits() != 0x00800000u32 ||
       F64_MIN_POSITIVE.to_bits() != 0x0010000000000000u64 {
        return 3
    }
    if F32_INFINITY.to_bits() != 0x7f800000u32 ||
       F64_INFINITY.to_bits() != 0x7ff0000000000000u64 ||
       F32_NEG_INFINITY.to_bits() != 0xff800000u32 ||
       F64_NEG_INFINITY.to_bits() != 0xfff0000000000000u64 {
        return 4
    }
    if !F32_NAN.is_nan() || !F64_NAN.is_nan() ||
       F32_INFINITY.is_finite() || F64_INFINITY.is_finite() ||
       F32_MIN_POSITIVE <= 0.0f32 || F64_MIN_POSITIVE <= 0.0f64 {
        return 5
    }
    if f32.DIGITS != F32_DIGITS || f64.DIGITS != F64_DIGITS ||
       f32.EPSILON.to_bits() != F32_EPSILON.to_bits() ||
       f64.EPSILON.to_bits() != F64_EPSILON.to_bits() ||
       f32.INFINITY.to_bits() != F32_INFINITY.to_bits() ||
       f64.INFINITY.to_bits() != F64_INFINITY.to_bits() ||
       f32.MANTISSA_DIGITS != F32_MANTISSA_DIGITS ||
       f64.MANTISSA_DIGITS != F64_MANTISSA_DIGITS ||
       f32.MAX_10_EXP != F32_MAX_10_EXP || f64.MAX_10_EXP != F64_MAX_10_EXP ||
       f32.MAX_EXP != F32_MAX_EXP || f64.MAX_EXP != F64_MAX_EXP ||
       f32.MIN_10_EXP != F32_MIN_10_EXP || f64.MIN_10_EXP != F64_MIN_10_EXP ||
       f32.MIN_EXP != F32_MIN_EXP || f64.MIN_EXP != F64_MIN_EXP ||
       f32.MIN_POSITIVE.to_bits() != F32_MIN_POSITIVE.to_bits() ||
       f64.MIN_POSITIVE.to_bits() != F64_MIN_POSITIVE.to_bits() ||
       !f32.NAN.is_nan() || !f64.NAN.is_nan() ||
       f32.NEG_INFINITY.to_bits() != F32_NEG_INFINITY.to_bits() ||
       f64.NEG_INFINITY.to_bits() != F64_NEG_INFINITY.to_bits() ||
       f32.RADIX != F32_RADIX || f64.RADIX != F64_RADIX {
        return 6
    }

    let inferredF32Digits = f32.DIGITS
    let inferredF64Digits = f64.DIGITS
    let inferredF32MaxExp = f32.MAX_EXP
    let inferredF64MinExp = f64.MIN_EXP
    let inferredF32Epsilon = f32.EPSILON
    let inferredF64MinPositive = f64.MIN_POSITIVE
    if inferredF32Digits != 6u32 || inferredF64Digits != 15u32 ||
       inferredF32MaxExp != 128i32 || inferredF64MinExp != -1021i32 ||
       inferredF32Epsilon.to_bits() != 0x34000000u32 ||
       inferredF64MinPositive.to_bits() != 0x0010000000000000u64 {
        return 7
    }
    0
}
