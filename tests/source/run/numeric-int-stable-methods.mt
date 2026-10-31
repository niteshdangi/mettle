// profiles: debug release

import core.num.Wrapping

fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(item) => false }
}

fn check_i8(): bool {
    let minimum = -128i8
    let (wrapped, overflow) = 2i8.overflowing_pow(7u32)
    let (wrappedMixed, mixedOverflow) = 127i8.overflowing_add_unsigned(1u8)
    let (wrappedQuotient, quotientOverflow) =
        minimum.overflowing_div_euclid(-1i8)
    let bigEndian = 0x1234i16.to_be_bytes()
    let littleEndian = 0x1234i16.to_le_bytes()
    minimum.unsigned_abs() == 128u8 &&
        (-5i8).abs_diff(3i8) == 8u8 &&
    15i8.ilog(2i8) == 3u32 &&
    100i8.ilog10() == 2u32 &&
    missing(0i8.checked_ilog2()) &&
    missing(10i8.checked_ilog(1i8)) &&
    missing((-10i8).checked_ilog2()) &&
    15i8.isqrt() == 3i8 &&
    missing((-1i8).checked_isqrt()) &&
    minimum.midpoint(127i8) == 0i8 &&
    (-5i8).signum() == -1i8 &&
        (-5i8).is_negative() &&
        5i8.is_positive() &&
        2i8.pow(3u32) == 8i8 &&
        missing(2i8.checked_pow(7u32)) &&
        2i8.wrapping_pow(7u32) == minimum &&
        2i8.saturating_pow(7u32) == 127i8 &&
        wrapped == -128i8 && overflow &&
        (-7i8).div_euclid(3i8) == -3i8 &&
        (-7i8).rem_euclid(3i8) == 2i8 &&
        missing(minimum.checked_div_euclid(-1i8)) &&
        missing(minimum.checked_rem_euclid(-1i8)) &&
        minimum.wrapping_div_euclid(-1i8) == minimum &&
        wrappedQuotient == minimum && quotientOverflow &&
        minimum.wrapping_rem_euclid(-1i8) == 0i8 &&
        1i8.add_unsigned(2u8) == 3i8 &&
        1i8.checked_add_unsigned(2u8) == present(3i8) &&
        127i8.wrapping_add_unsigned(1u8) == minimum &&
        missing(127i8.checked_add_unsigned(1u8)) &&
        127i8.saturating_add_unsigned(1u8) == 127i8 &&
        wrappedMixed == minimum && mixedOverflow &&
        5i8.sub_unsigned(3u8) == 2i8 &&
        (-1i8).cast_unsigned() == 255u8 &&
        i16.from_be_bytes([0x12u8, 0x34u8]) == 0x1234i16 &&
        bigEndian[0usize] == 0x12u8 && bigEndian[1usize] == 0x34u8 &&
        littleEndian[0usize] == 0x34u8 && littleEndian[1usize] == 0x12u8 &&
        i16.from_be(0x1234i16.to_be()) == 0x1234i16 &&
        i16.from_le(0x1234i16.to_le()) == 0x1234i16 &&
        i16.from_ne_bytes(0x1234i16.to_ne_bytes()) == 0x1234i16
}

fn check_i16(): bool {
    let minimum = -32768i16
    let (wrapped, overflow) = 2i16.overflowing_pow(15u32)
    minimum.unsigned_abs() == 32768u16 &&
        (-5i16).abs_diff(3i16) == 8u16 &&
        15i16.ilog2() == 3u32 &&
        81i16.isqrt() == 9i16 &&
        (-5i16).midpoint(2i16) == -1i16 &&
        (-5i16).signum() == -1i16 &&
        missing(2i16.checked_pow(15u32)) &&
        wrapped == minimum && overflow
}

fn check_i32(): bool {
    let minimum = -2147483648i32
    let (wrapped, overflow) = 2i32.overflowing_pow(31u32)
    minimum.unsigned_abs() == 2147483648u32 &&
        (-5i32).abs_diff(3i32) == 8u32 &&
        255u32.ilog2() == 7u32 &&
        100u32.checked_ilog10() == present(2u32) &&
        15u32.isqrt() == 3u32 &&
        missing(0u32.checked_isqrt()) == false &&
        9u32.next_power_of_two() == 16u32 &&
        9u32.checked_next_power_of_two() == present(16u32) &&
        20u32.div_ceil(6u32) == 4u32 &&
        10u32.next_multiple_of(4u32) == 12u32 &&
        10u32.checked_next_multiple_of(4u32) == present(12u32) &&
        missing(10u32.checked_next_multiple_of(0u32)) &&
        missing(4294967295u32.checked_next_multiple_of(2u32)) &&
        12u32.is_multiple_of(4u32) &&
        2147483647i32.midpoint(-2147483648i32) == 0i32 &&
        15i32.checked_ilog(2i32) == present(3u32) &&
        16i32.isqrt() == 4i32 &&
        (-1i32).cast_unsigned() == 4294967295u32 &&
        (-5i32).signum() == -1i32 &&
        (-5i32).is_negative() &&
        5i32.is_positive() &&
        2i32.pow(3u32) == 8i32 &&
        missing(2i32.checked_pow(31u32)) &&
        wrapped == minimum && overflow &&
        (-7i32).div_euclid(-3i32) == 3i32 &&
        (-7i32).rem_euclid(-3i32) == 2i32
}

fn check_i64(): bool {
    let minimum = -9223372036854775808i64
    let (wrapped, overflow) = 2i64.overflowing_pow(63u32)
    minimum.unsigned_abs() == 9223372036854775808u64 &&
        (-5i64).abs_diff(3i64) == 8u64 &&
        1000i64.ilog10() == 3u32 &&
        81i64.checked_isqrt() == present(9i64) &&
        (-5i64).midpoint(2i64) == -1i64 &&
        (-5i64).signum() == -1i64 &&
        2i64.pow(3u32) == 8i64 &&
        missing(2i64.checked_pow(63u32)) &&
        wrapped == minimum && overflow &&
        (-7i64).div_euclid(3i64) == -3i64 &&
        (-7i64).rem_euclid(3i64) == 2i64
}

fn check_i128(): bool {
    let minimum = -170141183460469231731687303715884105728i128
    let (wrapped, overflow) =
        2i128.overflowing_pow(127u32)
    minimum.unsigned_abs() == 170141183460469231731687303715884105728u128 &&
        (-5i128).abs_diff(3i128) == 8u128 &&
        81i128.isqrt() == 9i128 &&
        15i128.checked_ilog(2i128) == present(3u32) &&
        (-5i128).midpoint(2i128) == -1i128 &&
        (-5i128).signum() == -1i128 &&
        2i128.pow(3u32) == 8i128 &&
        missing(2i128.checked_pow(127u32)) &&
        wrapped == minimum && overflow &&
        (-7i128).div_euclid(-3i128) == 3i128 &&
        (-7i128).rem_euclid(-3i128) == 2i128
}

fn check_isize(): bool {
    let minimum = -9223372036854775808isize
    let (wrapped, overflow) = 2isize.overflowing_pow(63u32)
    minimum.unsigned_abs() == 9223372036854775808usize &&
        (-5isize).abs_diff(3isize) == 8usize &&
        16isize.ilog2() == 4u32 &&
        81isize.isqrt() == 9isize &&
        (-5isize).midpoint(2isize) == -1isize &&
        (-5isize).signum() == -1isize &&
        missing(2isize.checked_pow(63u32)) &&
        wrapped == minimum && overflow
}

fn check_unsigned(): bool {
    let (wrapped16, overflow16) = 2u16.overflowing_pow(16u32)
    let (wrapped8, overflow8) = 2u8.overflowing_pow(8u32)
    let (wrapped32, overflow32) = 2u32.overflowing_pow(32u32)
    let (wrapped64, overflow64) = 2u64.overflowing_pow(64u32)
    let (wrapped128, overflow128) = 2u128.overflowing_pow(128u32)
    let (mixedWrapped, mixedOverflow) = 1u8.overflowing_add_signed(-2i8)
    4u8.is_power_of_two() && !0u8.is_power_of_two() &&
    255u8.cast_signed() == -1i8 &&
    1u8.wrapping_add_signed(-2i8) == 255u8 &&
    missing(1u8.checked_add_signed(-2i8)) &&
    1u8.saturating_add_signed(-2i8) == 0u8 &&
    mixedWrapped == 255u8 && mixedOverflow &&
    3u8.sub_signed(-2i8) == 5u8 &&
    255u8.is_power_of_two() == false &&
    81u16.isqrt() == 9u16 &&
    1000u16.checked_ilog10() == present(3u32) &&
    5u16.midpoint(2u16) == 3u16 &&
    81u64.isqrt() == 9u64 &&
    1000u64.ilog10() == 3u32 &&
    5u64.midpoint(2u64) == 3u64 &&
    81u128.isqrt() == 9u128 &&
    1000u128.ilog10() == 3u32 &&
    5u128.midpoint(2u128) == 3u128 &&
    missing(129u8.checked_next_power_of_two()) &&
    0u8.checked_next_power_of_two() == present(1u8) &&
    0u8.is_multiple_of(0u8) && !1u8.is_multiple_of(0u8) &&
    0x41u8.is_ascii() &&
    0x41u8.is_ascii_alphabetic() &&
    0x41u8.is_ascii_alphanumeric() &&
    0x7fu8.is_ascii_control() &&
    0x31u8.is_ascii_digit() &&
    0x21u8.is_ascii_graphic() &&
    0x41u8.is_ascii_hexdigit() &&
    0x61u8.is_ascii_lowercase() &&
    0x21u8.is_ascii_punctuation() &&
    0x41u8.is_ascii_uppercase() &&
    0x20u8.is_ascii_whitespace() &&
    0x41u8.to_ascii_lowercase() == 0x61u8 &&
    0x61u8.to_ascii_uppercase() == 0x41u8 &&
    0x41u8.eq_ignore_ascii_case(0x61u8) &&
    2u8.saturating_pow(8u32) == 255u8 &&
        missing(2u16.checked_pow(16u32)) && wrapped16 == 0u16 &&
        overflow16 &&
        missing(2u8.checked_pow(8u32)) && wrapped8 == 0u8 && overflow8 &&
        missing(2u32.checked_pow(32u32)) && wrapped32 == 0u32 && overflow32 &&
        missing(2u64.checked_pow(64u32)) && wrapped64 == 0u64 && overflow64 &&
        missing(2u128.checked_pow(128u32)) && wrapped128 == 0u128 &&
        overflow128 &&
        2u8.pow(3u32) == 8u8 && 2u32.pow(3u32) == 8u32 &&
        2u64.pow(3u32) == 8u64 && 2u128.pow(3u32) == 8u128
}

fn check_shifts_and_wrapping(): bool {
    var letter = 0x41u8
    letter.make_ascii_lowercase()
    var lowerLetter = 0x61u8
    lowerLetter.make_ascii_uppercase()
    let shifted = unsafe { 1u8.unchecked_shl(3u32) }
    1u8.unbounded_shl(8u32) == 0u8 &&
        (-1i8).unbounded_shr(8u32) == -1i8 &&
        shifted == 8u8 &&
        letter == 0x61u8 &&
        lowerLetter == 0x41u8 &&
        Wrapping(1u8).reverse_bits().value == 128u8 &&
        Wrapping(1u16).reverse_bits().value == 32768u16 &&
        Wrapping(1u32).reverse_bits().value == 2147483648u32 &&
        Wrapping(1u64).reverse_bits().value ==
            9223372036854775808u64 &&
        Wrapping(1u128).reverse_bits().value ==
            170141183460469231731687303715884105728u128 &&
        Wrapping(1usize).reverse_bits().value ==
            9223372036854775808usize &&
        Wrapping(1i8).reverse_bits().value == -128i8 &&
        Wrapping(1i16).reverse_bits().value == -32768i16 &&
        Wrapping(1i32).reverse_bits().value == i32.MIN &&
        Wrapping(1i64).reverse_bits().value == i64.MIN &&
        Wrapping(1i128).reverse_bits().value == i128.MIN &&
        Wrapping(1isize).reverse_bits().value == isize.MIN
}

fn check_usize(): bool {
    let (wrapped, overflow) = 2usize.overflowing_pow(64u32)
    missing(2usize.checked_pow(64u32)) && wrapped == 0usize && overflow &&
        2usize.pow(3u32) == 8usize &&
        81usize.isqrt() == 9usize &&
        1000usize.ilog10() == 3u32 &&
        9usize.next_power_of_two() == 16usize
}

fn main(): i32 {
    if !check_i8() { return 1 }
    if !check_i16() { return 2 }
    if !check_i32() { return 3 }
    if !check_i64() { return 4 }
    if !check_i128() { return 5 }
    if !check_isize() { return 6 }
    if !check_unsigned() { return 7 }
    if !check_usize() { return 8 }
    if !check_shifts_and_wrapping() { return 9 }
    0
}
