fn missing<T: Copy>(value: T?): bool {
    match value { none => true, present(item) => false }
}

fn check_i8(): bool {
    let minimum = -128i8
    let maximum = 127i8
    let (sub, sub_overflow) = minimum.overflowing_sub(1i8)
    let (product, product_overflow) = maximum.overflowing_mul(2i8)
    let (quotient, div_overflow) = minimum.overflowing_div(-1i8)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1i8)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(8u32)
    let (right, right_overflow) = minimum.overflowing_shr(8u32)
    missing(minimum.checked_sub(1i8)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1i8) == maximum && minimum.saturating_sub(1i8) == minimum &&
        missing(maximum.checked_mul(2i8)) && product == -2i8 && product_overflow &&
        maximum.wrapping_mul(2i8) == -2i8 && maximum.saturating_mul(2i8) == maximum &&
        missing(minimum.checked_div(-1i8)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1i8) == minimum && minimum.saturating_div(-1i8) == maximum &&
        missing(minimum.checked_rem(-1i8)) && remainder == 0i8 && rem_overflow &&
        minimum.wrapping_rem(-1i8) == 0i8 &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(8u32)) && missing(minimum.checked_shr(8u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(8u32) == minimum && minimum.wrapping_shr(8u32) == minimum
}

fn check_i16(): bool {
    let minimum = -32768i16
    let maximum = 32767i16
    let (sub, sub_overflow) = minimum.overflowing_sub(1i16)
    let (product, product_overflow) = maximum.overflowing_mul(2i16)
    let (quotient, div_overflow) = minimum.overflowing_div(-1i16)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1i16)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(16u32)
    let (right, right_overflow) = minimum.overflowing_shr(16u32)
    missing(minimum.checked_sub(1i16)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1i16) == maximum && minimum.saturating_sub(1i16) == minimum &&
        missing(maximum.checked_mul(2i16)) && product == -2i16 && product_overflow &&
        maximum.wrapping_mul(2i16) == -2i16 && maximum.saturating_mul(2i16) == maximum &&
        missing(minimum.checked_div(-1i16)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1i16) == minimum && minimum.saturating_div(-1i16) == maximum &&
        missing(minimum.checked_rem(-1i16)) && remainder == 0i16 && rem_overflow &&
        minimum.wrapping_rem(-1i16) == 0i16 &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(16u32)) && missing(minimum.checked_shr(16u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(16u32) == minimum && minimum.wrapping_shr(16u32) == minimum
}

fn check_i32(): bool {
    let minimum = -2147483648i32
    let maximum = 2147483647i32
    let (sub, sub_overflow) = minimum.overflowing_sub(1i32)
    let (product, product_overflow) = maximum.overflowing_mul(2i32)
    let (quotient, div_overflow) = minimum.overflowing_div(-1i32)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1i32)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(32u32)
    let (right, right_overflow) = minimum.overflowing_shr(32u32)
    missing(minimum.checked_sub(1i32)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1i32) == maximum && minimum.saturating_sub(1i32) == minimum &&
        missing(maximum.checked_mul(2i32)) && product == -2i32 && product_overflow &&
        maximum.wrapping_mul(2i32) == -2i32 && maximum.saturating_mul(2i32) == maximum &&
        missing(minimum.checked_div(-1i32)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1i32) == minimum && minimum.saturating_div(-1i32) == maximum &&
        missing(minimum.checked_rem(-1i32)) && remainder == 0i32 && rem_overflow &&
        minimum.wrapping_rem(-1i32) == 0i32 &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(32u32)) && missing(minimum.checked_shr(32u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(32u32) == minimum && minimum.wrapping_shr(32u32) == minimum
}

fn check_i64(): bool {
    let minimum = -9223372036854775808i64
    let maximum = 9223372036854775807i64
    let (sub, sub_overflow) = minimum.overflowing_sub(1i64)
    let (product, product_overflow) = maximum.overflowing_mul(2i64)
    let (quotient, div_overflow) = minimum.overflowing_div(-1i64)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1i64)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(64u32)
    let (right, right_overflow) = minimum.overflowing_shr(64u32)
    missing(minimum.checked_sub(1i64)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1i64) == maximum && minimum.saturating_sub(1i64) == minimum &&
        missing(maximum.checked_mul(2i64)) && product == -2i64 && product_overflow &&
        maximum.wrapping_mul(2i64) == -2i64 && maximum.saturating_mul(2i64) == maximum &&
        missing(minimum.checked_div(-1i64)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1i64) == minimum && minimum.saturating_div(-1i64) == maximum &&
        missing(minimum.checked_rem(-1i64)) && remainder == 0i64 && rem_overflow &&
        minimum.wrapping_rem(-1i64) == 0i64 &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(64u32)) && missing(minimum.checked_shr(64u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(64u32) == minimum && minimum.wrapping_shr(64u32) == minimum
}

fn check_i128(): bool {
    let minimum = -170141183460469231731687303715884105728i128
    let maximum = 170141183460469231731687303715884105727i128
    let (sub, sub_overflow) = minimum.overflowing_sub(1i128)
    let (product, product_overflow) = maximum.overflowing_mul(2i128)
    let (quotient, div_overflow) = minimum.overflowing_div(-1i128)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1i128)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(128u32)
    let (right, right_overflow) = minimum.overflowing_shr(128u32)
    missing(minimum.checked_sub(1i128)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1i128) == maximum && minimum.saturating_sub(1i128) == minimum &&
        missing(maximum.checked_mul(2i128)) && product == -2i128 && product_overflow &&
        maximum.wrapping_mul(2i128) == -2i128 && maximum.saturating_mul(2i128) == maximum &&
        missing(minimum.checked_div(-1i128)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1i128) == minimum && minimum.saturating_div(-1i128) == maximum &&
        missing(minimum.checked_rem(-1i128)) && remainder == 0i128 && rem_overflow &&
        minimum.wrapping_rem(-1i128) == 0i128 &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(128u32)) && missing(minimum.checked_shr(128u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(128u32) == minimum && minimum.wrapping_shr(128u32) == minimum
}

fn check_isize(): bool {
    let minimum = -9223372036854775808isize
    let maximum = 9223372036854775807isize
    let (sub, sub_overflow) = minimum.overflowing_sub(1isize)
    let (product, product_overflow) = maximum.overflowing_mul(2isize)
    let (quotient, div_overflow) = minimum.overflowing_div(-1isize)
    let (remainder, rem_overflow) = minimum.overflowing_rem(-1isize)
    let (negative, neg_overflow) = minimum.overflowing_neg()
    let (magnitude, abs_overflow) = minimum.overflowing_abs()
    let (left, left_overflow) = minimum.overflowing_shl(64u32)
    let (right, right_overflow) = minimum.overflowing_shr(64u32)
    missing(minimum.checked_sub(1isize)) && sub == maximum && sub_overflow &&
        minimum.wrapping_sub(1isize) == maximum && minimum.saturating_sub(1isize) == minimum &&
        missing(maximum.checked_mul(2isize)) && product == -2isize && product_overflow &&
        maximum.wrapping_mul(2isize) == -2isize && maximum.saturating_mul(2isize) == maximum &&
        missing(minimum.checked_div(-1isize)) && quotient == minimum && div_overflow &&
        minimum.wrapping_div(-1isize) == minimum && minimum.saturating_div(-1isize) == maximum &&
        missing(minimum.checked_rem(-1isize)) && remainder == 0isize && rem_overflow &&
        minimum.wrapping_rem(-1isize) == 0isize &&
        missing(minimum.checked_neg()) && negative == minimum && neg_overflow &&
        minimum.wrapping_neg() == minimum && minimum.saturating_neg() == maximum &&
        missing(minimum.checked_abs()) && magnitude == minimum && abs_overflow &&
        minimum.wrapping_abs() == minimum && minimum.saturating_abs() == maximum &&
        missing(minimum.checked_shl(64u32)) && missing(minimum.checked_shr(64u32)) &&
        left == minimum && left_overflow && right == minimum && right_overflow &&
        minimum.wrapping_shl(64u32) == minimum && minimum.wrapping_shr(64u32) == minimum
}

fn main(): i32 {
    if check_i8() && check_i16() && check_i32() && check_i64() &&
       check_i128() && check_isize() { 0 } else { 1 }
}
