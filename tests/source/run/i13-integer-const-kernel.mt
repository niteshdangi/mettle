// profiles: debug release

macro scalar_constants {
    ($name:ident, $result:ident, $type:ident) => {
        const fn $name(): i32 {
            let zero = 0 as $type
            let one = 1 as $type
            let two = 2 as $type
            let three = 3 as $type
            let all = zero.wrapping_sub(one)
            let width = $type.BITS
            let top = one.wrapping_shl(width - 1u32)
            if zero.count_ones() != 0u32 || zero.count_zeros() != width ||
               all.count_ones() != width || all.count_zeros() != 0u32 { return 1 }
            if zero.leading_zeros() != width || zero.trailing_zeros() != width ||
               all.leading_ones() != width || all.trailing_ones() != width ||
               three.leading_zeros() != width - 2u32 ||
               three.trailing_ones() != 2u32 { return 2 }
            match zero.highest_one() { none => {}, present(_) => { return 3 } }
            match zero.lowest_one() { none => {}, present(_) => { return 3 } }
            match top.highest_one() {
                present(index) => { if index != width - 1u32 { return 3 } },
                none => { return 3 }
            }
            match top.lowest_one() {
                present(index) => { if index != width - 1u32 { return 3 } },
                none => { return 3 }
            }
            if all.isolate_highest_one() != top || all.isolate_lowest_one() != one ||
               zero.isolate_highest_one() != zero || zero.isolate_lowest_one() != zero ||
               one.reverse_bits() != top || all.reverse_bits() != all { return 4 }
            if one.rotate_left(u32.MAX) != top || one.rotate_right(u32.MAX) != two ||
               top.rotate_left(1u32) != one || three.rotate_right(width) != three { return 5 }
            match one.checked_shl(width) { none => {}, present(_) => { return 6 } }
            match one.checked_shr(u32.MAX) { none => {}, present(_) => { return 6 } }
            match top.checked_shl(1u32) {
                present(value) => { if value != zero { return 6 } },
                none => { return 6 }
            }
            match three.checked_shr(1u32) {
                present(value) => { if value != one { return 6 } },
                none => { return 6 }
            }
            let left = one.overflowing_shl(width)
            let right = one.overflowing_shr(u32.MAX)
            let discarded = top.overflowing_shl(1u32)
            if left.0 != one || !left.1 || right.0 != zero || !right.1 ||
               discarded.0 != zero || discarded.1 { return 7 }
            if one.wrapping_shl(u32.MAX) != top || one.wrapping_shr(u32.MAX) != zero ||
               one.unbounded_shl(u32.MAX) != zero || one.unbounded_shr(u32.MAX) != zero ||
               three.strict_shl(1u32) != 6 as $type ||
               three.strict_shr(1u32) != one { return 8 }
            if unsafe { three.unchecked_shl(1u32) } != 6 as $type ||
               unsafe { three.unchecked_shr(1u32) } != one { return 8 }

            let value = 0x5a as $type
            let big = value.to_be_bytes()
            let little = value.to_le_bytes()
            let scalar_big = value.to_be().to_ne_bytes()
            let scalar_little = value.to_le().to_ne_bytes()
            let negative_bytes = all.to_ne_bytes()
            let bytes = (width / 8u32) as usize
            var index = 0usize
            while index < bytes {
                let expected_big = if index == bytes - 1usize { 0x5au8 } else { 0u8 }
                let expected_little = if index == 0usize { 0x5au8 } else { 0u8 }
                if big[index] != expected_big || little[index] != expected_little ||
                   scalar_big[index] != expected_big ||
                   scalar_little[index] != expected_little ||
                   negative_bytes[index] != 255u8 { return 9 }
                index += 1usize
            }
            if $type.from_be_bytes(big) != value || $type.from_le_bytes(little) != value ||
               $type.from_ne_bytes(value.to_ne_bytes()) != value ||
               $type.from_be(value.to_be()) != value ||
               $type.from_le(value.to_le()) != value ||
               value.swap_bytes() != value.wrapping_shl(width - 8u32) ||
               all.swap_bytes() != all { return 10 }
            var high_big = [0u8; ($type.BITS / 8u32) as usize]
            var high_little = high_big
            high_big[0usize] = 0x80u8
            high_little[bytes - 1usize] = 0x80u8
            let ones = [255u8; ($type.BITS / 8u32) as usize]
            if $type.from_be_bytes(high_big) != top ||
               $type.from_le_bytes(high_little) != top ||
               $type.from_ne_bytes(ones) != all { return 10 }
            let top_big = top.to_be_bytes()
            let top_little = top.to_le_bytes()
            index = 0usize
            while index < bytes {
                if top_big[index] != high_big[index] ||
                   top_little[index] != high_little[index] { return 10 }
                index += 1usize
            }

            let fifteen = 15 as $type
            if fifteen.ilog(three) != 2u32 || fifteen.ilog2() != 3u32 ||
               (99 as $type).ilog10() != 1u32 { return 11 }
            match fifteen.checked_ilog(three) {
                present(value) => { if value != 2u32 { return 12 } },
                none => { return 12 }
            }
            match fifteen.checked_ilog2() {
                present(value) => { if value != 3u32 { return 12 } },
                none => { return 12 }
            }
            match (99 as $type).checked_ilog10() {
                present(value) => { if value != 1u32 { return 12 } },
                none => { return 12 }
            }
            match zero.checked_ilog2() { none => {}, present(_) => { return 13 } }
            match zero.checked_ilog10() { none => {}, present(_) => { return 13 } }
            match fifteen.checked_ilog(one) { none => {}, present(_) => { return 13 } }
            if zero.isqrt() != zero || (80 as $type).isqrt() != 8 as $type ||
               (81 as $type).isqrt() != 9 as $type { return 14 }
            if $type.MAX.midpoint($type.MAX) != $type.MAX { return 15 }

            match $type.MIN.checked_sub(one) { none => {}, present(_) => { return 16 } }
            match three.checked_sub(one) {
                present(value) => { if value != two { return 16 } },
                none => { return 16 }
            }
            let subtract = $type.MIN.overflowing_sub(one)
            if subtract.0 != $type.MAX || !subtract.1 ||
               $type.MIN.wrapping_sub(one) != $type.MAX ||
               $type.MIN.saturating_sub(one) != $type.MIN ||
               three.strict_sub(one) != two { return 17 }
            match $type.MAX.checked_mul(two) { none => {}, present(_) => { return 18 } }
            match three.checked_mul(two) {
                present(value) => { if value != 6 as $type { return 18 } },
                none => { return 18 }
            }
            let product = $type.MAX.overflowing_mul(two)
            let exact = three.overflowing_mul(two)
            if product.0 != all.wrapping_sub(one) || !product.1 ||
               exact.0 != 6 as $type || exact.1 ||
               $type.MAX.wrapping_mul(two) != all.wrapping_sub(one) ||
               $type.MAX.saturating_mul(two) != $type.MAX ||
               three.strict_mul(two) != 6 as $type { return 19 }
            if one.strict_add(two) != three ||
               $type.MAX.saturating_add(one) != $type.MAX ||
               unsafe { one.unchecked_add(two) } != three ||
               unsafe { three.unchecked_sub(one) } != two ||
               unsafe { three.unchecked_mul(two) } != 6 as $type ||
               two.pow(3u32) != 8 as $type || two.strict_pow(3u32) != 8 as $type { return 20 }
            let nine = 9 as $type
            match nine.checked_div(two) {
                present(value) => { if value != 4 as $type { return 21 } },
                none => { return 21 }
            }
            match nine.checked_div_euclid(two) {
                present(value) => { if value != 4 as $type { return 21 } },
                none => { return 21 }
            }
            match nine.checked_rem(two) {
                present(value) => { if value != one { return 21 } },
                none => { return 21 }
            }
            match nine.checked_rem_euclid(two) {
                present(value) => { if value != one { return 21 } },
                none => { return 21 }
            }
            match nine.checked_rem(zero) { none => {}, present(_) => { return 22 } }
            match nine.checked_div_euclid(zero) { none => {}, present(_) => { return 22 } }
            match nine.checked_rem_euclid(zero) { none => {}, present(_) => { return 22 } }
            if nine.strict_div(two) != 4 as $type ||
               nine.strict_div_euclid(two) != 4 as $type ||
               nine.strict_rem(two) != one || nine.strict_rem_euclid(two) != one ||
               nine.div_euclid(two) != 4 as $type || nine.rem_euclid(two) != one { return 23 }
            0
        }
        const $result: i32 = $name()
    };
}

macro signed_constants {
    ($name:ident, $result:ident, $type:ident, $unsigned:ident) => {
        const fn $name(): i32 {
            let zero = 0 as $type
            let one = 1 as $type
            let minus_one = -1 as $type
            let negative = -3 as $type
            if negative.abs() != 3 as $type || negative.strict_abs() != 3 as $type ||
               negative.strict_neg() != 3 as $type ||
               unsafe { negative.unchecked_neg() } != 3 as $type { return 31 }
            match $type.MIN.checked_abs() { none => {}, present(_) => { return 32 } }
            match $type.MIN.checked_neg() { none => {}, present(_) => { return 32 } }
            match negative.checked_neg() {
                present(value) => { if value != 3 as $type { return 32 } },
                none => { return 32 }
            }
            match negative.checked_abs() {
                present(value) => { if value != 3 as $type { return 32 } },
                none => { return 32 }
            }
            let absolute = $type.MIN.overflowing_abs()
            let negated = $type.MIN.overflowing_neg()
            if absolute.0 != $type.MIN || !absolute.1 ||
               negated.0 != $type.MIN || !negated.1 ||
               $type.MIN.wrapping_abs() != $type.MIN ||
               $type.MIN.wrapping_neg() != $type.MIN ||
               $type.MIN.saturating_abs() != $type.MAX ||
               $type.MIN.saturating_neg() != $type.MAX { return 33 }
            let top = (1 as $unsigned).wrapping_shl($type.BITS - 1u32)
            if $type.MIN.unsigned_abs() != top ||
               minus_one.cast_unsigned() != $unsigned.MAX ||
               $type.MIN.abs_diff($type.MAX) != $unsigned.MAX { return 34 }
            if negative.signum() != minus_one || zero.signum() != zero ||
               one.signum() != one || !negative.is_negative() || negative.is_positive() ||
               !one.is_positive() || zero.is_negative() || zero.is_positive() { return 35 }
            if $type.MIN.midpoint($type.MAX) != zero ||
               $type.MIN.midpoint($type.MIN) != $type.MIN ||
               (-4 as $type).midpoint(one) != minus_one ||
               $type.MIN.unbounded_shr(u32.MAX) != minus_one ||
               $type.MIN.wrapping_shr(u32.MAX) != minus_one { return 36 }
            match negative.checked_isqrt() { none => {}, present(_) => { return 37 } }
            match (81 as $type).checked_isqrt() {
                present(value) => { if value != 9 as $type { return 37 } },
                none => { return 37 }
            }
            match negative.checked_ilog2() { none => {}, present(_) => { return 38 } }
            match one.checked_ilog(negative) { none => {}, present(_) => { return 38 } }
            match $type.MIN.checked_add_unsigned($unsigned.MAX) {
                present(value) => { if value != $type.MAX { return 39 } },
                none => { return 39 }
            }
            match $type.MAX.checked_sub_unsigned($unsigned.MAX) {
                present(value) => { if value != $type.MIN { return 39 } },
                none => { return 39 }
            }
            match $type.MAX.checked_add_unsigned(1 as $unsigned) {
                none => {}, present(_) => { return 40 }
            }
            match $type.MIN.checked_sub_unsigned(1 as $unsigned) {
                none => {}, present(_) => { return 40 }
            }
            let added = $type.MAX.overflowing_add_unsigned(1 as $unsigned)
            let subtracted = $type.MIN.overflowing_sub_unsigned(1 as $unsigned)
            if added.0 != $type.MIN || !added.1 ||
               subtracted.0 != $type.MAX || !subtracted.1 ||
               $type.MAX.wrapping_add_unsigned(1 as $unsigned) != $type.MIN ||
               $type.MIN.wrapping_sub_unsigned(1 as $unsigned) != $type.MAX ||
               $type.MAX.saturating_add_unsigned(1 as $unsigned) != $type.MAX ||
               $type.MIN.saturating_sub_unsigned(1 as $unsigned) != $type.MIN ||
               one.strict_add_unsigned(1 as $unsigned) != 2 as $type ||
               one.strict_sub_unsigned(1 as $unsigned) != zero { return 41 }
            0
        }
        const $result: i32 = $name()
    };
}

macro unsigned_constants {
    ($name:ident, $result:ident, $type:ident, $signed:ident) => {
        const fn $name(): i32 {
            let zero = 0 as $type
            let one = 1 as $type
            let two = 2 as $type
            let top = one.wrapping_shl($type.BITS - 1u32)
            let minus_one = -1 as $signed
            if $type.MAX.cast_signed() != minus_one ||
               zero.abs_diff($type.MAX) != $type.MAX ||
               $type.MAX.midpoint(one) != top ||
               zero.bit_width() != 0u32 || $type.MAX.bit_width() != $type.BITS { return 51 }
            if !top.is_power_of_two() || zero.is_power_of_two() || $type.MAX.is_power_of_two() ||
               zero.next_power_of_two() != one ||
               (9 as $type).next_power_of_two() != 16 as $type { return 52 }
            match top.checked_next_power_of_two() {
                present(value) => { if value != top { return 53 } },
                none => { return 53 }
            }
            match $type.MAX.checked_next_power_of_two() {
                none => {}, present(_) => { return 53 }
            }
            if $type.MAX.div_ceil(two) != top || $type.MAX.div_ceil($type.MAX) != one ||
               (7 as $type).next_multiple_of(4 as $type) != 8 as $type ||
               !zero.is_multiple_of(zero) || one.is_multiple_of(zero) ||
               !$type.MAX.is_multiple_of(one) { return 54 }
            match (7 as $type).checked_next_multiple_of(4 as $type) {
                present(value) => { if value != 8 as $type { return 55 } },
                none => { return 55 }
            }
            match $type.MAX.checked_next_multiple_of(two) {
                none => {}, present(_) => { return 55 }
            }
            match zero.checked_next_multiple_of(zero) {
                none => {}, present(_) => { return 55 }
            }
            match zero.checked_signed_diff(top) {
                present(value) => { if value != $signed.MIN { return 56 } },
                none => { return 56 }
            }
            match top.checked_signed_diff(zero) { none => {}, present(_) => { return 56 } }
            match $type.MAX.checked_signed_diff($type.MAX) {
                present(value) => { if value != 0 as $signed { return 56 } },
                none => { return 56 }
            }
            let root = one.wrapping_shl($type.BITS / 2u32) - one
            if $type.MAX.isqrt() != root || top.unbounded_shr(u32.MAX) != zero { return 57 }
            match one.checked_neg() { none => {}, present(_) => { return 58 } }
            let negated = one.overflowing_neg()
            if one.wrapping_neg() != $type.MAX || negated.0 != $type.MAX ||
               !negated.1 || zero.strict_neg() != zero { return 58 }
            match $type.MAX.checked_add_signed($signed.MIN) {
                present(value) => { if value != top - one { return 59 } },
                none => { return 59 }
            }
            match $type.MAX.checked_sub_signed($signed.MAX) {
                present(value) => { if value != top { return 59 } },
                none => { return 59 }
            }
            match zero.checked_add_signed(minus_one) { none => {}, present(_) => { return 60 } }
            match $type.MAX.checked_sub_signed(minus_one) {
                none => {}, present(_) => { return 60 }
            }
            let added = zero.overflowing_add_signed(minus_one)
            let subtracted = $type.MAX.overflowing_sub_signed(minus_one)
            if added.0 != $type.MAX || !added.1 || subtracted.0 != zero || !subtracted.1 ||
               zero.wrapping_add_signed(minus_one) != $type.MAX ||
               $type.MAX.wrapping_sub_signed(minus_one) != zero ||
               zero.saturating_add_signed(minus_one) != zero ||
               $type.MAX.saturating_sub_signed(minus_one) != $type.MAX ||
               one.strict_add_signed(minus_one) != zero ||
               one.strict_sub_signed(minus_one) != two { return 61 }
            0
        }
        const $result: i32 = $name()
    };
}

scalar_constants!(scalar_i8, SCALAR_I8, i8)
scalar_constants!(scalar_i16, SCALAR_I16, i16)
scalar_constants!(scalar_i32, SCALAR_I32, i32)
scalar_constants!(scalar_i64, SCALAR_I64, i64)
scalar_constants!(scalar_i128, SCALAR_I128, i128)
scalar_constants!(scalar_isize, SCALAR_ISIZE, isize)
scalar_constants!(scalar_u8, SCALAR_U8, u8)
scalar_constants!(scalar_u16, SCALAR_U16, u16)
scalar_constants!(scalar_u32, SCALAR_U32, u32)
scalar_constants!(scalar_u64, SCALAR_U64, u64)
scalar_constants!(scalar_u128, SCALAR_U128, u128)
scalar_constants!(scalar_usize, SCALAR_USIZE, usize)
signed_constants!(signed_i8, SIGNED_I8, i8, u8)
signed_constants!(signed_i16, SIGNED_I16, i16, u16)
signed_constants!(signed_i32, SIGNED_I32, i32, u32)
signed_constants!(signed_i64, SIGNED_I64, i64, u64)
signed_constants!(signed_i128, SIGNED_I128, i128, u128)
signed_constants!(signed_isize, SIGNED_ISIZE, isize, usize)
unsigned_constants!(unsigned_u8, UNSIGNED_U8, u8, i8)
unsigned_constants!(unsigned_u16, UNSIGNED_U16, u16, i16)
unsigned_constants!(unsigned_u32, UNSIGNED_U32, u32, i32)
unsigned_constants!(unsigned_u64, UNSIGNED_U64, u64, i64)
unsigned_constants!(unsigned_u128, UNSIGNED_U128, u128, i128)
unsigned_constants!(unsigned_usize, UNSIGNED_USIZE, usize, isize)

const fn ascii_constants(): i32 {
    if !0x41u8.is_ascii() || 0x80u8.is_ascii() ||
       !0x41u8.is_ascii_alphabetic() || 0x31u8.is_ascii_alphabetic() ||
       !0x31u8.is_ascii_alphanumeric() || 0x21u8.is_ascii_alphanumeric() { return 71 }
    if !0x7fu8.is_ascii_control() || 0x20u8.is_ascii_control() ||
       !0x31u8.is_ascii_digit() || 0x41u8.is_ascii_digit() ||
       !0x21u8.is_ascii_graphic() || 0x20u8.is_ascii_graphic() { return 72 }
    if !0x46u8.is_ascii_hexdigit() || 0x47u8.is_ascii_hexdigit() ||
       !0x61u8.is_ascii_lowercase() || 0x41u8.is_ascii_lowercase() ||
       !0x21u8.is_ascii_punctuation() || 0x41u8.is_ascii_punctuation() ||
       !0x41u8.is_ascii_uppercase() || 0x61u8.is_ascii_uppercase() { return 73 }
    if !0x0cu8.is_ascii_whitespace() || 0x0bu8.is_ascii_whitespace() ||
       0x80u8.to_ascii_lowercase() != 0x80u8 ||
       0x80u8.to_ascii_uppercase() != 0x80u8 ||
       0x41u8.to_ascii_lowercase() != 0x61u8 ||
       0x61u8.to_ascii_uppercase() != 0x41u8 ||
       !0x41u8.eq_ignore_ascii_case(0x61u8) ||
       0xc1u8.eq_ignore_ascii_case(0xe1u8) { return 74 }
    var letter = 0x41u8
    letter.make_ascii_lowercase()
    if letter != 0x61u8 { return 75 }
    letter.make_ascii_uppercase()
    if letter != 0x41u8 { return 75 }
    var non_ascii = 0xe1u8
    non_ascii.make_ascii_uppercase()
    non_ascii.make_ascii_lowercase()
    if non_ascii != 0xe1u8 { return 75 }
    0
}

const ASCII: i32 = ascii_constants()
const WIDE_PRODUCT: (u128, bool) = u128.MAX.overflowing_mul(u128.MAX)
const WIDE_LOG: u32 = u128.MAX.ilog(3u128)
const WIDE_DECIMAL_LOG: u32 = u128.MAX.ilog10()
const WIDE_ROOT: u128 = u128.MAX.isqrt()

fn main(): i32 {
    let codes = [
        SCALAR_I8, SCALAR_I16, SCALAR_I32, SCALAR_I64, SCALAR_I128, SCALAR_ISIZE,
        SCALAR_U8, SCALAR_U16, SCALAR_U32, SCALAR_U64, SCALAR_U128, SCALAR_USIZE,
        SIGNED_I8, SIGNED_I16, SIGNED_I32, SIGNED_I64, SIGNED_I128, SIGNED_ISIZE,
        UNSIGNED_U8, UNSIGNED_U16, UNSIGNED_U32, UNSIGNED_U64, UNSIGNED_U128, UNSIGNED_USIZE,
        ASCII
    ]
    var index = 0usize
    while index < 25usize {
        if codes[index] != 0 { return codes[index] }
        index += 1usize
    }
    if WIDE_PRODUCT.0 != 1u128 || !WIDE_PRODUCT.1 || WIDE_LOG != 80u32 ||
       WIDE_DECIMAL_LOG != 38u32 || WIDE_ROOT != 18446744073709551615u128 { return 76 }
    0
}
