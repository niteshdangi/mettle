// expect-exit: 0
// profiles: debug release

import core.convert.{From, Into, TryFrom}
import core.float

fn from_value<S, T: From<S>>(take value: S): T {
    T.(From<S>).from(value)
}

fn into_value<S, T: From<S>>(take value: S): T {
    S.(Into<T>).into(value)
}

fn try_identity<T: TryFrom<T>>(
    take value: T
): (Outcome<T, T.(TryFrom<T>).Error>) {
    T.(TryFrom<T>).try_from(value)
}

fn main(): i32 {
    let f32_false: f32 = from_value(false)
    let f32_true: f32 = from_value(true)
    let f64_false: f64 = from_value(false)
    let f64_true: f64 = from_value(true)
    if f32_false.to_bits() != 0u32 || f32_true.to_bits() != 0x3f800000u32 ||
       f64_false.to_bits() != 0u64 || f64_true.to_bits() != 0x3ff0000000000000u64 {
        return 1
    }

    let f32_i8_min: f32 = from_value(i8.MIN)
    let f32_i8_max: f32 = from_value(i8.MAX)
    let f32_i16_min: f32 = from_value(i16.MIN)
    let f32_i16_max: f32 = from_value(i16.MAX)
    let f32_u8_min: f32 = from_value(u8.MIN)
    let f32_u8_max: f32 = from_value(u8.MAX)
    let f32_u16_min: f32 = from_value(u16.MIN)
    let f32_u16_max: f32 = from_value(u16.MAX)
    if f32_i8_min != -128.0f32 || f32_i8_max != 127.0f32 ||
       f32_i16_min != -32768.0f32 || f32_i16_max != 32767.0f32 ||
       f32_u8_min != 0.0f32 || f32_u8_max != 255.0f32 ||
       f32_u16_min != 0.0f32 || f32_u16_max != 65535.0f32 {
        return 2
    }

    let f64_i8_min: f64 = from_value(i8.MIN)
    let f64_i8_max: f64 = from_value(i8.MAX)
    let f64_i16_min: f64 = from_value(i16.MIN)
    let f64_i16_max: f64 = from_value(i16.MAX)
    let f64_i32_min: f64 = from_value(i32.MIN)
    let f64_i32_max: f64 = from_value(i32.MAX)
    let f64_u8_min: f64 = from_value(u8.MIN)
    let f64_u8_max: f64 = from_value(u8.MAX)
    let f64_u16_min: f64 = from_value(u16.MIN)
    let f64_u16_max: f64 = from_value(u16.MAX)
    let f64_u32_min: f64 = from_value(u32.MIN)
    let f64_u32_max: f64 = from_value(u32.MAX)
    if f64_i8_min != -128.0f64 || f64_i8_max != 127.0f64 ||
       f64_i16_min != -32768.0f64 || f64_i16_max != 32767.0f64 ||
       f64_i32_min != -2147483648.0f64 || f64_i32_max != 2147483647.0f64 ||
       f64_u8_min != 0.0f64 || f64_u8_max != 255.0f64 ||
       f64_u16_min != 0.0f64 || f64_u16_max != 65535.0f64 ||
       f64_u32_min != 0.0f64 || f64_u32_max != 4294967295.0f64 {
        return 3
    }

    let via_into_u16: f32 = into_value(u16.MAX)
    let via_into_bool: f64 = into_value(true)
    if via_into_u16 != 65535.0f32 || via_into_bool != 1.0f64 {
        return 4
    }

    let widened_one: f64 = from_value(1.5f32)
    let widened_min_subnormal: f64 = from_value(f32.from_bits(1u32))
    let widened_max_finite: f64 = from_value(f32.MAX)
    let widened_min_finite: f64 = from_value(f32.MIN)
    let widened_positive_zero: f64 = from_value(0.0f32)
    let widened_negative_zero: f64 = from_value(-0.0f32)
    if widened_one.to_bits() != 0x3ff8000000000000u64 ||
       widened_min_subnormal.to_bits() != 0x36a0000000000000u64 ||
       widened_max_finite.to_bits() != 0x47efffffe0000000u64 ||
       widened_min_finite.to_bits() != 0xc7efffffe0000000u64 ||
       widened_positive_zero.to_bits() != 0u64 ||
       widened_negative_zero.to_bits() != 0x8000000000000000u64 {
        return 5
    }

    let widened_quiet_nan: f64 = from_value(f32.from_bits(0x7fc12345u32))
    let widened_signaling_nan: f64 = from_value(f32.from_bits(0xff812345u32))
    if !widened_quiet_nan.is_nan() || !widened_signaling_nan.is_nan() {
        return 6
    }

    let via_into_widening: f64 = into_value(-0.0f32)
    if via_into_widening.to_bits() != 0x8000000000000000u64 {
        return 7
    }

    match try_identity(via_into_widening) {
        success(value) => {
            if value.to_bits() != 0x8000000000000000u64 { return 8 }
        }
    }
    0
}
