import core.float

fn bits64(value: f64): u64 { value.to_bits() }
fn bits32(value: f32): u32 { value.to_bits() }
fn nan64(value: f64): bool { value.is_nan() }
fn nan32(value: f32): bool { value.is_nan() }
fn ones(value: usize): u32 { value.count_ones() }

fn main(): i32 {
    if bits64(f64.MAX) != 0x7fefffffffffffffu64 { return 1 }
    if bits64(f64.MIN) != 0xffefffffffffffffu64 { return 2 }
    if bits64(f64.MIN_POSITIVE) != 0x0010000000000000u64 { return 3 }
    if bits64(f64.EPSILON) != 0x3cb0000000000000u64 { return 4 }
    if bits64(f64.INFINITY) != 0x7ff0000000000000u64 { return 5 }
    if bits64(f64.NEG_INFINITY) != 0xfff0000000000000u64 { return 6 }
    if !nan64(f64.NAN) || bits64(f64.NAN) != 0x7ff8000000000000u64 { return 7 }
    if bits32(f32.MAX) != 0x7f7fffffu32 { return 8 }
    if bits32(f32.MIN) != 0xff7fffffu32 { return 9 }
    if bits32(f32.MIN_POSITIVE) != 0x00800000u32 { return 10 }
    if bits32(f32.EPSILON) != 0x34000000u32 { return 11 }
    if bits32(f32.INFINITY) != 0x7f800000u32 { return 12 }
    if bits32(f32.NEG_INFINITY) != 0xff800000u32 { return 13 }
    if !nan32(f32.NAN) || bits32(f32.NAN) != 0x7fc00000u32 { return 14 }
    if f64.RADIX != 2u32 || f32.RADIX != 2u32 { return 15 }
    if f64.MANTISSA_DIGITS != 53u32 || f32.MANTISSA_DIGITS != 24u32 { return 16 }
    if f64.DIGITS != 15u32 || f32.DIGITS != 6u32 { return 17 }
    if f64.MIN_EXP != -1021 || f64.MAX_EXP != 1024 { return 18 }
    if f64.MIN_10_EXP != -307 || f64.MAX_10_EXP != 308 { return 19 }
    if f32.MIN_EXP != -125 || f32.MAX_EXP != 128 { return 20 }
    if f32.MIN_10_EXP != -37 || f32.MAX_10_EXP != 38 { return 21 }
    if f64.EPSILON != 1.0f64.next_up() - 1.0f64 { return 22 }
    if f32.EPSILON != 1.0f32.next_up() - 1.0f32 { return 23 }
    if u8.BITS != 8u32 || i8.BITS != 8u32 || u16.BITS != 16u32 || i16.BITS != 16u32 { return 24 }
    if u32.BITS != 32u32 || i32.BITS != 32u32 || u64.BITS != 64u32 || i64.BITS != 64u32 { return 25 }
    if u128.BITS != 128u32 || i128.BITS != 128u32 { return 26 }
    if usize.BITS != ones(usize.MAX) || isize.BITS != ones(usize.MAX) { return 27 }
    0
}
