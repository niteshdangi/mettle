fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(item) => false }
}

fn check_u8(): bool {
    let zero = 0u8
    let maximum = 255u8
    let (sub, sub_overflow) = zero.overflowing_sub(1u8)
    let (product, product_overflow) = maximum.overflowing_mul(2u8)
    let (quotient, div_overflow) = maximum.overflowing_div(2u8)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2u8)
    let (negative, neg_overflow) = 1u8.overflowing_neg()
    let (left, left_overflow) = 1u8.overflowing_shl(8u32)
    let (right, right_overflow) = 1u8.overflowing_shr(8u32)
    missing(zero.checked_sub(1u8)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1u8) == maximum && zero.saturating_sub(1u8) == zero &&
        missing(maximum.checked_mul(2u8)) && product == 254u8 && product_overflow &&
        maximum.wrapping_mul(2u8) == 254u8 && maximum.saturating_mul(2u8) == maximum &&
        missing(maximum.checked_div(0u8)) && missing(maximum.checked_rem(0u8)) &&
        !missing(maximum.checked_div(2u8)) && quotient == 127u8 && !div_overflow &&
        maximum.wrapping_div(2u8) == 127u8 && maximum.saturating_div(2u8) == 127u8 &&
        !missing(maximum.checked_rem(2u8)) && remainder == 1u8 && !rem_overflow &&
        maximum.wrapping_rem(2u8) == 1u8 &&
        missing(1u8.checked_neg()) && negative == maximum && neg_overflow &&
        1u8.wrapping_neg() == maximum && 1u8.saturating_neg() == zero &&
        missing(1u8.checked_shl(8u32)) && missing(1u8.checked_shr(8u32)) &&
        left == 1u8 && left_overflow && right == 1u8 && right_overflow &&
        1u8.wrapping_shl(8u32) == 1u8 && 1u8.wrapping_shr(8u32) == 1u8
}

fn check_u16(): bool {
    let zero = 0u16
    let maximum = 65535u16
    let (sub, sub_overflow) = zero.overflowing_sub(1u16)
    let (product, product_overflow) = maximum.overflowing_mul(2u16)
    let (quotient, div_overflow) = maximum.overflowing_div(2u16)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2u16)
    let (negative, neg_overflow) = 1u16.overflowing_neg()
    let (left, left_overflow) = 1u16.overflowing_shl(16u32)
    let (right, right_overflow) = 1u16.overflowing_shr(16u32)
    missing(zero.checked_sub(1u16)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1u16) == maximum && zero.saturating_sub(1u16) == zero &&
        missing(maximum.checked_mul(2u16)) && product == 65534u16 && product_overflow &&
        maximum.wrapping_mul(2u16) == 65534u16 && maximum.saturating_mul(2u16) == maximum &&
        missing(maximum.checked_div(0u16)) && missing(maximum.checked_rem(0u16)) &&
        !missing(maximum.checked_div(2u16)) && quotient == 32767u16 && !div_overflow &&
        maximum.wrapping_div(2u16) == 32767u16 && maximum.saturating_div(2u16) == 32767u16 &&
        !missing(maximum.checked_rem(2u16)) && remainder == 1u16 && !rem_overflow &&
        maximum.wrapping_rem(2u16) == 1u16 &&
        missing(1u16.checked_neg()) && negative == maximum && neg_overflow &&
        1u16.wrapping_neg() == maximum && 1u16.saturating_neg() == zero &&
        missing(1u16.checked_shl(16u32)) && missing(1u16.checked_shr(16u32)) &&
        left == 1u16 && left_overflow && right == 1u16 && right_overflow &&
        1u16.wrapping_shl(16u32) == 1u16 && 1u16.wrapping_shr(16u32) == 1u16
}

fn check_u32(): bool {
    let zero = 0u32
    let maximum = 4294967295u32
    let (sub, sub_overflow) = zero.overflowing_sub(1u32)
    let (product, product_overflow) = maximum.overflowing_mul(2u32)
    let (quotient, div_overflow) = maximum.overflowing_div(2u32)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2u32)
    let (negative, neg_overflow) = 1u32.overflowing_neg()
    let (left, left_overflow) = 1u32.overflowing_shl(32u32)
    let (right, right_overflow) = 1u32.overflowing_shr(32u32)
    missing(zero.checked_sub(1u32)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1u32) == maximum && zero.saturating_sub(1u32) == zero &&
        missing(maximum.checked_mul(2u32)) && product == 4294967294u32 && product_overflow &&
        maximum.wrapping_mul(2u32) == 4294967294u32 && maximum.saturating_mul(2u32) == maximum &&
        missing(maximum.checked_div(0u32)) && missing(maximum.checked_rem(0u32)) &&
        !missing(maximum.checked_div(2u32)) && quotient == 2147483647u32 && !div_overflow &&
        maximum.wrapping_div(2u32) == 2147483647u32 && maximum.saturating_div(2u32) == 2147483647u32 &&
        !missing(maximum.checked_rem(2u32)) && remainder == 1u32 && !rem_overflow &&
        maximum.wrapping_rem(2u32) == 1u32 &&
        missing(1u32.checked_neg()) && negative == maximum && neg_overflow &&
        1u32.wrapping_neg() == maximum && 1u32.saturating_neg() == zero &&
        missing(1u32.checked_shl(32u32)) && missing(1u32.checked_shr(32u32)) &&
        left == 1u32 && left_overflow && right == 1u32 && right_overflow &&
        1u32.wrapping_shl(32u32) == 1u32 && 1u32.wrapping_shr(32u32) == 1u32
}

fn check_u64(): bool {
    let zero = 0u64
    let maximum = 18446744073709551615u64
    let (sub, sub_overflow) = zero.overflowing_sub(1u64)
    let (product, product_overflow) = maximum.overflowing_mul(2u64)
    let (quotient, div_overflow) = maximum.overflowing_div(2u64)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2u64)
    let (negative, neg_overflow) = 1u64.overflowing_neg()
    let (left, left_overflow) = 1u64.overflowing_shl(64u32)
    let (right, right_overflow) = 1u64.overflowing_shr(64u32)
    missing(zero.checked_sub(1u64)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1u64) == maximum && zero.saturating_sub(1u64) == zero &&
        missing(maximum.checked_mul(2u64)) && product == 18446744073709551614u64 && product_overflow &&
        maximum.wrapping_mul(2u64) == 18446744073709551614u64 && maximum.saturating_mul(2u64) == maximum &&
        missing(maximum.checked_div(0u64)) && missing(maximum.checked_rem(0u64)) &&
        !missing(maximum.checked_div(2u64)) && quotient == 9223372036854775807u64 && !div_overflow &&
        maximum.wrapping_div(2u64) == 9223372036854775807u64 && maximum.saturating_div(2u64) == 9223372036854775807u64 &&
        !missing(maximum.checked_rem(2u64)) && remainder == 1u64 && !rem_overflow &&
        maximum.wrapping_rem(2u64) == 1u64 &&
        missing(1u64.checked_neg()) && negative == maximum && neg_overflow &&
        1u64.wrapping_neg() == maximum && 1u64.saturating_neg() == zero &&
        missing(1u64.checked_shl(64u32)) && missing(1u64.checked_shr(64u32)) &&
        left == 1u64 && left_overflow && right == 1u64 && right_overflow &&
        1u64.wrapping_shl(64u32) == 1u64 && 1u64.wrapping_shr(64u32) == 1u64
}

fn check_u128(): bool {
    let zero = 0u128
    let maximum = 340282366920938463463374607431768211455u128
    let (sub, sub_overflow) = zero.overflowing_sub(1u128)
    let (product, product_overflow) = maximum.overflowing_mul(2u128)
    let (quotient, div_overflow) = maximum.overflowing_div(2u128)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2u128)
    let (negative, neg_overflow) = 1u128.overflowing_neg()
    let (left, left_overflow) = 1u128.overflowing_shl(128u32)
    let (right, right_overflow) = 1u128.overflowing_shr(128u32)
    missing(zero.checked_sub(1u128)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1u128) == maximum && zero.saturating_sub(1u128) == zero &&
        missing(maximum.checked_mul(2u128)) && product == 340282366920938463463374607431768211454u128 && product_overflow &&
        maximum.wrapping_mul(2u128) == 340282366920938463463374607431768211454u128 && maximum.saturating_mul(2u128) == maximum &&
        missing(maximum.checked_div(0u128)) && missing(maximum.checked_rem(0u128)) &&
        !missing(maximum.checked_div(2u128)) && quotient == 170141183460469231731687303715884105727u128 && !div_overflow &&
        maximum.wrapping_div(2u128) == 170141183460469231731687303715884105727u128 && maximum.saturating_div(2u128) == 170141183460469231731687303715884105727u128 &&
        !missing(maximum.checked_rem(2u128)) && remainder == 1u128 && !rem_overflow &&
        maximum.wrapping_rem(2u128) == 1u128 &&
        missing(1u128.checked_neg()) && negative == maximum && neg_overflow &&
        1u128.wrapping_neg() == maximum && 1u128.saturating_neg() == zero &&
        missing(1u128.checked_shl(128u32)) && missing(1u128.checked_shr(128u32)) &&
        left == 1u128 && left_overflow && right == 1u128 && right_overflow &&
        1u128.wrapping_shl(128u32) == 1u128 && 1u128.wrapping_shr(128u32) == 1u128
}

fn check_usize(): bool {
    let zero = 0usize
    let maximum = 18446744073709551615usize
    let (sub, sub_overflow) = zero.overflowing_sub(1usize)
    let (product, product_overflow) = maximum.overflowing_mul(2usize)
    let (quotient, div_overflow) = maximum.overflowing_div(2usize)
    let (remainder, rem_overflow) = maximum.overflowing_rem(2usize)
    let (negative, neg_overflow) = 1usize.overflowing_neg()
    let (left, left_overflow) = 1usize.overflowing_shl(64u32)
    let (right, right_overflow) = 1usize.overflowing_shr(64u32)
    missing(zero.checked_sub(1usize)) && sub == maximum && sub_overflow &&
        zero.wrapping_sub(1usize) == maximum && zero.saturating_sub(1usize) == zero &&
        missing(maximum.checked_mul(2usize)) && product == 18446744073709551614usize && product_overflow &&
        maximum.wrapping_mul(2usize) == 18446744073709551614usize && maximum.saturating_mul(2usize) == maximum &&
        missing(maximum.checked_div(0usize)) && missing(maximum.checked_rem(0usize)) &&
        !missing(maximum.checked_div(2usize)) && quotient == 9223372036854775807usize && !div_overflow &&
        maximum.wrapping_div(2usize) == 9223372036854775807usize && maximum.saturating_div(2usize) == 9223372036854775807usize &&
        !missing(maximum.checked_rem(2usize)) && remainder == 1usize && !rem_overflow &&
        maximum.wrapping_rem(2usize) == 1usize &&
        missing(1usize.checked_neg()) && negative == maximum && neg_overflow &&
        1usize.wrapping_neg() == maximum && 1usize.saturating_neg() == zero &&
        missing(1usize.checked_shl(64u32)) && missing(1usize.checked_shr(64u32)) &&
        left == 1usize && left_overflow && right == 1usize && right_overflow &&
        1usize.wrapping_shl(64u32) == 1usize && 1usize.wrapping_shr(64u32) == 1usize
}

fn main(): i32 {
    if check_u8() && check_u16() && check_u32() && check_u64() &&
       check_u128() && check_usize() { 0 } else { 1 }
}
