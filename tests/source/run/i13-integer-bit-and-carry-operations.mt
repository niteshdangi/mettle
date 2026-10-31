import core.num

fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(item) => false }
}

fn isolate(value: u128): u128 { value.isolate_highest_one() }

fn max64_width(): u32 {
    let top = u64.MAX
    top.bit_width()
}

fn main(): i32 {
    if !missing(0u8.highest_one()) || !missing(0i64.lowest_one()) { return 1 }
    if 0b0010_1000u8.highest_one() != present(5u32) { return 2 }
    if 0b0010_1000u8.lowest_one() != present(3u32) { return 3 }
    if (-128i8).highest_one() != present(7u32) { return 4 }
    if (-1i32).lowest_one() != present(0u32) { return 5 }
    if 0b0010_1100u8.isolate_highest_one() != 0b0010_0000u8 { return 6 }
    if 0b0010_1100u8.isolate_lowest_one() != 0b0000_0100u8 { return 7 }
    if (-1i8).isolate_highest_one() != -128i8 { return 8 }
    if (-8i16).isolate_lowest_one() != 8i16 { return 9 }
    if 0u128.isolate_highest_one() != 0u128 || 0i32.isolate_lowest_one() != 0i32 { return 10 }
    if isolate(u128.MAX) != 1u128 << 127u128 { return 11 }
    if 0u16.bit_width() != 0u32 || 1u16.bit_width() != 1u32 || 255u8.bit_width() != 8u32 { return 12 }
    if max64_width() != 64u32 || 256u32.bit_width() != 9u32 { return 13 }
    if 5u8.checked_signed_diff(3u8) != present(2i8) { return 14 }
    if 3u8.checked_signed_diff(5u8) != present(-2i8) { return 15 }
    if !missing(200u8.checked_signed_diff(0u8)) { return 16 }
    if !missing(0u8.checked_signed_diff(129u8)) { return 17 }
    if 0u8.checked_signed_diff(128u8) != present(-128i8) { return 18 }
    if 127u8.checked_signed_diff(0u8) != present(127i8) { return 19 }

    let (sum, carry) = 250u8.carrying_add(5u8, false)
    if sum != 255u8 || carry { return 20 }
    let (wrapped, wrapped_carry) = 250u8.carrying_add(5u8, true)
    if wrapped != 0u8 || !wrapped_carry { return 21 }
    let (maximum, maximum_carry) = 255u8.carrying_add(255u8, true)
    if maximum != 255u8 || !maximum_carry { return 22 }
    let (difference, borrow) = 5u8.borrowing_sub(3u8, true)
    if difference != 1u8 || borrow { return 23 }
    let (borrowed, borrowed_flag) = 0u8.borrowing_sub(0u8, true)
    if borrowed != 255u8 || !borrowed_flag { return 24 }
    let (signed_sum, signed_overflow) = 127i8.carrying_add(0i8, true)
    if signed_sum != -128i8 || !signed_overflow { return 25 }
    let (signed_ok, signed_ok_flag) = (-128i8).carrying_add(127i8, true)
    if signed_ok != 0i8 || signed_ok_flag { return 26 }
    let (signed_diff, signed_borrow) = (-128i8).borrowing_sub(0i8, true)
    if signed_diff != 127i8 || !signed_borrow { return 27 }

    let max64 = u64.MAX
    let max_size = usize.MAX
    let min64 = i64.MIN
    let max128 = u128.MAX
    let min128 = i128.MIN
    let min8 = i8.MIN
    let (low, high) = 200u8.carrying_mul(100u8, 7u8)
    if low != 0x27u8 || high != 0x4eu8 { return 28 }
    let (low_added, high_added) = 255u8.carrying_mul_add(255u8, 255u8, 255u8)
    if low_added != 0xffu8 || high_added != 0xffu8 { return 29 }
    let (signed_low, signed_high) = (-100i8).carrying_mul(100i8, 0i8)
    if signed_low != 0xf0u8 || signed_high != -40i8 { return 30 }
    let (signed_low_two, signed_high_two) = min8.carrying_mul(min8, 0i8)
    if signed_low_two != 0u8 || signed_high_two != 64i8 { return 31 }
    let (low64, high64) = max64.carrying_mul(max64, 0u64)
    if low64 != 1u64 || high64 != 0xfffffffffffffffeu64 { return 32 }
    let (low64_added, high64_added) = max64.carrying_mul_add(max64, max64, max64)
    if low64_added != u64.MAX || high64_added != u64.MAX { return 33 }
    let (size_low, size_high) = max_size.carrying_mul(2usize, 1usize)
    if size_low != usize.MAX || size_high != 1usize { return 34 }
    let (neg_low, neg_high) = min64.carrying_mul(2i64, 0i64)
    if neg_low != 0u64 || neg_high != -1i64 { return 35 }

    let (low128, high128) = max128.carrying_mul(max128, 0u128)
    if low128 != 1u128 || high128 != u128.MAX - 1u128 { return 36 }
    let (full_low, full_high) = max128.carrying_mul_add(max128, max128, max128)
    if full_low != u128.MAX || full_high != u128.MAX { return 37 }
    let (mixed_low, mixed_high) = (1u128 << 64u128).carrying_mul(1u128 << 64u128, 5u128)
    if mixed_low != 5u128 || mixed_high != 1u128 { return 38 }
    let (signed128_low, signed128_high) = min128.carrying_mul(min128, 0i128)
    if signed128_low != 0u128 || signed128_high != 1i128 << 126i128 { return 39 }
    let (negative_low, negative_high) = (-1i128).carrying_mul(1i128, 0i128)
    if negative_low != u128.MAX || negative_high != -1i128 { return 40 }
    let (carried_low, carried_high) = (-3i128).carrying_mul(2i128, -1i128)
    if carried_low != u128.MAX - 6u128 || carried_high != -1i128 { return 41 }
    let (zeroed_low, zeroed_high) = 1i128.carrying_mul(1i128, -1i128)
    if zeroed_low != 0u128 || zeroed_high != 0i128 { return 42 }
    0
}
