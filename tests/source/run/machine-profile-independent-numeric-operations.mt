
fn main() {
    let minimum = -128i8
    let (wrapped,overflow) = 127i8.overflowing_add(1)
    let checked = match 1u64.checked_sub(2) { none => 42, present(value) => 1 }
    let (negated,neg_overflow) = minimum.overflowing_neg()
    let (remainder,rem_overflow) = minimum.overflowing_rem(-1)
    let a = 1.0000000000000002f64
    let b = 0.9999999999999998f64
    let nan = f64.from_bits(0x7ff8000000000042u64)
    let infinity = f64.from_bits(0x7ff0000000000000u64)
    if wrapped == -128i8 && overflow && checked == 42 &&
       minimum.wrapping_neg() == minimum && minimum.saturating_neg() == 127i8 &&
       250u8.saturating_add(20) == 255u8 &&
       2u8.saturating_sub(20) == 0u8 &&
       negated == minimum && neg_overflow && remainder == 0i8 && rem_overflow &&
       1u8.wrapping_shl(9) == 2u8 &&
       1u8.rotate_left(9) == 2u8 &&
       0u128.leading_zeros() == 128u32 && 255u8.count_ones() == 8u32 &&
       0x1234u16.swap_bytes() == 0x3412u16 &&
       1u8.reverse_bits() == 128u8 &&
       nan.to_bits() == 0x7ff8000000000042u64 && nan.is_nan() &&
       !nan.is_finite() && !nan.is_normal() && !nan.is_subnormal() &&
       infinity.is_infinite() && !infinity.is_finite() &&
       (-0.0f32).is_sign_negative() && !(-0.0f32).is_sign_positive() &&
       1e-45f32.is_subnormal() && !1e-45f32.is_normal() &&
       1.0f32.is_normal() && (-0.0f32).abs().to_bits() == 0u32 &&
       (-2.25f64).abs() == 2.25f64 && 4.0f64.sqrt() == 2.0f64 &&
       (-2.25f64).floor() == -3.0f64 && (-2.25f64).ceil() == -2.0f64 &&
       (-2.25f64).trunc() == -2.0f64 && (-2.25f64).round() == -2.0f64 &&
       2.5f64.round_ties_even() == 2.0f64 &&
       (-2.5f64).round_ties_even() == -2.0f64 &&
       3.5f64.copysign(-0.0f64) == -3.5f64 &&
       f64.from_bits(nan.to_bits()).to_bits() == nan.to_bits() &&
       a.mul_add(b,-1.0f64) != a * b - 1.0f64 { 0 } else { 1 }
}
