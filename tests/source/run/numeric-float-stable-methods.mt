import core.float.{FpCategory}
import core.cmp.Ordering

fn close(left: f64, right: f64): bool {
    (left - right).abs() < 0.0001f64
}

fn check_f64(): bool {
    let nan = f64.from_bits(0x7ff8000000000042u64)
    let negativeZero = f64.from_bits(0x8000000000000000u64)
    let subnormal = f64.from_bits(1u64)
    let infinity = f64.from_bits(0x7ff0000000000000u64)
    let negativeInfinity = f64.from_bits(0xfff0000000000000u64)
    let (sine, cosine) = 0.0f64.sin_cos()
    close(0.0f64.sin(), 0.0f64) &&
        close(0.0f64.cos(), 1.0f64) &&
        close(0.0f64.tan(), 0.0f64) &&
        close(0.0f64.asin(), 0.0f64) &&
        close(1.0f64.acos(), 0.0f64) &&
        close(0.0f64.atan(), 0.0f64) &&
        close(1.0f64.atan2(1.0f64), 0.7853981633974483f64) &&
        close(0.0f64.sinh(), 0.0f64) &&
        close(0.0f64.cosh(), 1.0f64) &&
        close(0.0f64.tanh(), 0.0f64) &&
        close(0.0f64.asinh(), 0.0f64) &&
        close(1.0f64.acosh(), 0.0f64) &&
        close(0.0f64.atanh(), 0.0f64) &&
        close(0.0f64.exp(), 1.0f64) &&
        close(3.0f64.exp2(), 8.0f64) &&
        close(0.0f64.exp_m1(), 0.0f64) &&
        close(1.0f64.ln(), 0.0f64) &&
        close(0.0f64.ln_1p(), 0.0f64) &&
        close(8.0f64.log(2.0f64), 3.0f64) &&
        close(8.0f64.log2(), 3.0f64) &&
        close(100.0f64.log10(), 2.0f64) &&
        close(2.0f64.powf(3.0f64), 8.0f64) &&
        close(2.0f64.powi(3i32), 8.0f64) &&
        close(27.0f64.cbrt(), 3.0f64) &&
        close(3.0f64.hypot(4.0f64), 5.0f64) &&
        sine == 0.0f64 && cosine == 1.0f64 &&
        (-1.25f64).fract() == -0.25f64 &&
        negativeZero.fract().is_sign_negative() &&
        4.0f64.recip() == 0.25f64 &&
        (-2.0f64).signum() == -1.0f64 &&
        close(3.141592653589793f64.to_degrees(), 180.0f64) &&
        close(180.0f64.to_radians(), 3.141592653589793f64) &&
        (-7.0f64).div_euclid(3.0f64) == -2.0f64 &&
        (-7.0f64).rem_euclid(3.0f64) == 2.0f64 &&
        2.0f64.midpoint(4.0f64) == 3.0f64 &&
        1.0f64.next_up() > 1.0f64 &&
        1.0f64.next_down() < 1.0f64 &&
        infinity.next_up() == infinity &&
        infinity.next_down().is_finite() &&
        infinity.midpoint(1.0f64) == infinity &&
        infinity.midpoint(negativeInfinity).is_nan() &&
        infinity.fract().is_nan() &&
        2.0f64.min(nan) == 2.0f64 &&
        2.0f64.max(3.0f64) == 3.0f64 &&
        5.0f64.clamp(1.0f64, 3.0f64) == 3.0f64 &&
        nan.classify() == FpCategory.Nan &&
        nan.is_nan() && !nan.is_finite() &&
        infinity.classify() == FpCategory.Infinite &&
        infinity.is_infinite() &&
        negativeZero.classify() == FpCategory.Zero &&
        negativeZero.is_sign_negative() &&
        subnormal.classify() == FpCategory.Subnormal &&
        !subnormal.is_normal() &&
        negativeZero.midpoint(negativeZero).is_sign_negative() &&
        0.0f64.min(negativeZero).is_sign_negative() &&
        0.0f64.max(negativeZero).to_bits() == 0u64 &&
        negativeZero.next_up().to_bits() == 1u64 &&
        0.0f64.next_down().to_bits() == 0x8000000000000001u64 &&
        1.0f64.classify() == FpCategory.Normal &&
        i64.from_be_bytes(1.0f64.to_be_bytes()) == 4607182418800017408i64 &&
        1.0f64.to_be_bytes() ==
            [0x3fu8, 0xf0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8] &&
        f64.from_ne_bytes(1.0f64.to_ne_bytes()) == 1.0f64 &&
        f64.from_be_bytes([0x3fu8, 0xf0u8, 0u8, 0u8, 0u8, 0u8, 0u8, 0u8]) ==
            1.0f64
}

fn check_f32(): bool {
    let nan = f32.from_bits(0x7fc00042u32)
    let negativeZero = f32.from_bits(0x80000000u32)
    let subnormal = f32.from_bits(1u32)
    let infinity = f32.from_bits(0x7f800000u32)
    let negativeInfinity = f32.from_bits(0xff800000u32)
    let (sine, cosine) = 0.0f32.sin_cos()
    close(0.0f32.sin() as f64, 0.0f64) &&
        0.0f32.tan() == 0.0f32 &&
        0.0f32.asin() == 0.0f32 &&
        1.0f32.acos() == 0.0f32 &&
        0.0f32.atan() == 0.0f32 &&
        0.0f32.cos() == 1.0f32 &&
        close(1.0f32.atan2(1.0f32) as f64, 0.7853981633974483f64) &&
        0.0f32.sinh() == 0.0f32 &&
        0.0f32.cosh() == 1.0f32 &&
        0.0f32.tanh() == 0.0f32 &&
        0.0f32.asinh() == 0.0f32 &&
        1.0f32.acosh() == 0.0f32 &&
        0.0f32.atanh() == 0.0f32 &&
        0.0f32.exp() == 1.0f32 &&
        3.0f32.exp2() == 8.0f32 &&
        0.0f32.exp_m1() == 0.0f32 &&
        1.0f32.ln() == 0.0f32 &&
        0.0f32.ln_1p() == 0.0f32 &&
        close(8.0f32.log(2.0f32) as f64, 3.0f64) &&
        close(8.0f32.log2() as f64, 3.0f64) &&
        close(100.0f32.log10() as f64, 2.0f64) &&
        close(2.0f32.powf(3.0f32) as f64, 8.0f64) &&
        close(2.0f32.powi(3i32) as f64, 8.0f64) &&
        close(27.0f32.cbrt() as f64, 3.0f64) &&
        close(3.0f32.hypot(4.0f32) as f64, 5.0f64) &&
        (-2.25f32).floor() == -3.0f32 &&
        (-2.25f32).ceil() == -2.0f32 &&
        (-2.25f32).trunc() == -2.0f32 &&
        2.5f32.round() == 3.0f32 &&
        2.5f32.round_ties_even() == 2.0f32 &&
        2.0f32.min(nan) == 2.0f32 &&
        2.0f32.max(3.0f32) == 3.0f32 &&
        5.0f32.clamp(1.0f32, 3.0f32) == 3.0f32 &&
        close(3.1415927f32.to_degrees() as f64, 180.0f64) &&
        close(180.0f32.to_radians() as f64, 3.1415927f64) &&
        sine == 0.0f32 && cosine == 1.0f32 &&
        (-1.25f32).fract() == -0.25f32 &&
        negativeZero.fract().is_sign_negative() &&
        4.0f32.recip() == 0.25f32 &&
        (-2.0f32).signum() == -1.0f32 &&
        (-7.0f32).div_euclid(3.0f32) == -2.0f32 &&
        (-7.0f32).rem_euclid(3.0f32) == 2.0f32 &&
        2.0f32.midpoint(4.0f32) == 3.0f32 &&
        1.0f32.next_up() > 1.0f32 &&
        1.0f32.next_down() < 1.0f32 &&
        infinity.next_up() == infinity &&
        infinity.next_down().is_finite() &&
        infinity.midpoint(negativeInfinity).is_nan() &&
        infinity.fract().is_nan() &&
        nan.classify() == FpCategory.Nan &&
        negativeZero.classify() == FpCategory.Zero &&
        negativeZero.is_sign_negative() &&
        negativeZero.midpoint(negativeZero).is_sign_negative() &&
        negativeZero.next_up().to_bits() == 1u32 &&
        0.0f32.next_down().to_bits() == 0x80000001u32 &&
        subnormal.classify() == FpCategory.Subnormal &&
        1.0f32.is_finite() && !infinity.is_finite() &&
        f32.from_le_bytes([0u8, 0u8, 0x80u8, 0x3fu8]) == 1.0f32 &&
        f32.from_be_bytes([0x3fu8, 0x80u8, 0u8, 0u8]) == 1.0f32 &&
        f32.from_ne_bytes(1.0f32.to_ne_bytes()) == 1.0f32 &&
        1.0f32.to_be_bytes() == [0x3fu8, 0x80u8, 0u8, 0u8] &&
        1.0f32.to_le_bytes() == [0u8, 0u8, 0x80u8, 0x3fu8] &&
        nan.total_cmp(nan) == Ordering.Equal
}

fn main(): i32 {
    if !check_f64() { return 1 }
    if !check_f32() { return 2 }
    0
}
