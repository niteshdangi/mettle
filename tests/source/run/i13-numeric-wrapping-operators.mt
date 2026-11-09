// profiles: debug release

import core.cmp.PartialEq
import core.num.Wrapping
import core.ops.{ Add, AddAssign, BitAnd, BitAndAssign, BitOr, BitOrAssign }
import core.ops.{ BitXor, BitXorAssign, Div, DivAssign, Mul, MulAssign }
import core.ops.{ Neg, Not, Rem, RemAssign, Shl, ShlAssign }
import core.ops.{ Shr, ShrAssign, Sub, SubAssign }

fn add_read_operands<T: Copy>(
    read left: Wrapping<T>,
    read right: Wrapping<T>
): Wrapping<T>
where Wrapping<T>: Add<Wrapping<T>, Output = Wrapping<T>>
{
    left + right
}

fn check_binary<T: Copy + PartialEq>(
    maximum: T,
    minimum: T,
    zero: T,
    one: T,
    two: T,
    minus_one: T,
    add_overflow: T,
    sub_overflow: T,
    mul_overflow: T,
    maximum_half: T
): bool
where Wrapping<T>: Add<Wrapping<T>, Output = Wrapping<T>> + Sub<Wrapping<T>, Output = Wrapping<T>> + Mul<Wrapping<T>, Output = Wrapping<T>> + Div<Wrapping<T>, Output = Wrapping<T>> + Rem<Wrapping<T>, Output = Wrapping<T>> + BitAnd<Wrapping<T>, Output = Wrapping<T>> + BitOr<Wrapping<T>, Output = Wrapping<T>> + BitXor<Wrapping<T>, Output = Wrapping<T>>
{
    (Wrapping(maximum) + Wrapping(one)).value == add_overflow &&
        add_read_operands(Wrapping(maximum), Wrapping(one)).value == add_overflow &&
        (Wrapping(minimum) - Wrapping(one)).value == sub_overflow &&
        (Wrapping(maximum) * Wrapping(two)).value == mul_overflow &&
        (Wrapping(minimum) / Wrapping(minus_one)).value == minimum &&
        (Wrapping(minimum) % Wrapping(minus_one)).value == zero &&
        (Wrapping(maximum) / Wrapping(two)).value == maximum_half &&
        (Wrapping(maximum) % Wrapping(two)).value == one &&
        (Wrapping(maximum) & Wrapping(zero)).value == zero &&
        (Wrapping(maximum) | Wrapping(zero)).value == maximum &&
        (Wrapping(maximum) ^ Wrapping(maximum)).value == zero
}

fn check_unary<T: Copy + PartialEq>(
    zero: T,
    one: T,
    minimum: T,
    maximum: T,
    negative_one: T
): bool
where Wrapping<T>: Neg<Output = Wrapping<T>> + Not<Output = Wrapping<T>>
{
    (-Wrapping(one)).value == negative_one &&
        (-Wrapping(minimum)).value == minimum &&
        (!Wrapping(zero)).value == negative_one &&
        (!Wrapping(maximum)).value == minimum
}

fn check_shifts<T: Copy + PartialEq>(
    one: T,
    two: T,
    maximum: T,
    maximum_half: T,
    width: usize
): bool
where Wrapping<T>: Shl<usize, Output = Wrapping<T>> + Shr<usize, Output = Wrapping<T>>
{
    (Wrapping(one) << width).value == one &&
        (Wrapping(one) << (width + 1usize)).value == two &&
        (Wrapping(maximum) >> width).value == maximum &&
        (Wrapping(maximum) >> (width + 1usize)).value == maximum_half
}

fn check_assignments<T: Copy + PartialEq>(
    maximum: T,
    minimum: T,
    zero: T,
    one: T,
    two: T,
    minus_one: T,
    add_overflow: T,
    sub_overflow: T,
    mul_overflow: T,
    maximum_half: T,
    width: usize
): bool
where Wrapping<T>: AddAssign<Wrapping<T>> + AddAssign<T> + SubAssign<Wrapping<T>> + SubAssign<T> + MulAssign<Wrapping<T>> + MulAssign<T> + DivAssign<Wrapping<T>> + DivAssign<T> + RemAssign<Wrapping<T>> + RemAssign<T> + BitAndAssign<Wrapping<T>> + BitAndAssign<T> + BitOrAssign<Wrapping<T>> + BitOrAssign<T> + BitXorAssign<Wrapping<T>> + BitXorAssign<T> + ShlAssign<usize> + ShrAssign<usize>
{
    var add_wrapped = Wrapping(maximum)
    add_wrapped += Wrapping(one)
    if add_wrapped.value != add_overflow { return false }
    var add_scalar = Wrapping(maximum)
    add_scalar += one
    if add_scalar.value != add_overflow { return false }

    var sub_wrapped = Wrapping(minimum)
    sub_wrapped -= Wrapping(one)
    if sub_wrapped.value != sub_overflow { return false }
    var sub_scalar = Wrapping(minimum)
    sub_scalar -= one
    if sub_scalar.value != sub_overflow { return false }

    var mul_wrapped = Wrapping(maximum)
    mul_wrapped *= Wrapping(two)
    if mul_wrapped.value != mul_overflow { return false }
    var mul_scalar = Wrapping(maximum)
    mul_scalar *= two
    if mul_scalar.value != mul_overflow { return false }

    var div_wrapped = Wrapping(minimum)
    div_wrapped /= Wrapping(minus_one)
    if div_wrapped.value != minimum { return false }
    var div_scalar = Wrapping(minimum)
    div_scalar /= minus_one
    if div_scalar.value != minimum { return false }

    var rem_wrapped = Wrapping(minimum)
    rem_wrapped %= Wrapping(minus_one)
    if rem_wrapped.value != zero { return false }
    var rem_scalar = Wrapping(minimum)
    rem_scalar %= minus_one
    if rem_scalar.value != zero { return false }

    var and_wrapped = Wrapping(maximum)
    and_wrapped &= Wrapping(zero)
    if and_wrapped.value != zero { return false }
    var and_scalar = Wrapping(maximum)
    and_scalar &= zero
    if and_scalar.value != zero { return false }

    var or_wrapped = Wrapping(maximum)
    or_wrapped |= Wrapping(zero)
    if or_wrapped.value != maximum { return false }
    var or_scalar = Wrapping(maximum)
    or_scalar |= zero
    if or_scalar.value != maximum { return false }

    var xor_wrapped = Wrapping(maximum)
    xor_wrapped ^= Wrapping(maximum)
    if xor_wrapped.value != zero { return false }
    var xor_scalar = Wrapping(maximum)
    xor_scalar ^= maximum
    if xor_scalar.value != zero { return false }

    var left = Wrapping(one)
    left <<= width
    if left.value != one { return false }
    left = Wrapping(one)
    left <<= width + 1usize
    if left.value != two { return false }

    var right = Wrapping(maximum)
    right >>= width
    if right.value != maximum { return false }
    right = Wrapping(maximum)
    right >>= width + 1usize
    right.value == maximum_half
}

fn main(): i32 {
    if !check_binary(i8.MAX, i8.MIN, 0i8, 1i8, 2i8, -1i8,
        i8.MIN, i8.MAX, -2i8, i8.MAX / 2i8) ||
        !check_unary(0i8, 1i8, i8.MIN, i8.MAX, -1i8) ||
        !check_shifts(1i8, 2i8, i8.MAX, i8.MAX / 2i8, 8usize) ||
        !check_assignments(i8.MAX, i8.MIN, 0i8, 1i8, 2i8, -1i8,
            i8.MIN, i8.MAX, -2i8, i8.MAX / 2i8, 8usize) {
        return 1
    }
    if !check_binary(i16.MAX, i16.MIN, 0i16, 1i16, 2i16, -1i16,
        i16.MIN, i16.MAX, -2i16, i16.MAX / 2i16) ||
        !check_unary(0i16, 1i16, i16.MIN, i16.MAX, -1i16) ||
        !check_shifts(1i16, 2i16, i16.MAX, i16.MAX / 2i16, 16usize) ||
        !check_assignments(i16.MAX, i16.MIN, 0i16, 1i16, 2i16, -1i16,
            i16.MIN, i16.MAX, -2i16, i16.MAX / 2i16, 16usize) {
        return 2
    }
    if !check_binary(i32.MAX, i32.MIN, 0i32, 1i32, 2i32, -1i32,
        i32.MIN, i32.MAX, -2i32, i32.MAX / 2i32) ||
        !check_unary(0i32, 1i32, i32.MIN, i32.MAX, -1i32) ||
        !check_shifts(1i32, 2i32, i32.MAX, i32.MAX / 2i32, 32usize) ||
        !check_assignments(i32.MAX, i32.MIN, 0i32, 1i32, 2i32, -1i32,
            i32.MIN, i32.MAX, -2i32, i32.MAX / 2i32, 32usize) {
        return 3
    }
    if !check_binary(i64.MAX, i64.MIN, 0i64, 1i64, 2i64, -1i64,
        i64.MIN, i64.MAX, -2i64, i64.MAX / 2i64) ||
        !check_unary(0i64, 1i64, i64.MIN, i64.MAX, -1i64) ||
        !check_shifts(1i64, 2i64, i64.MAX, i64.MAX / 2i64, 64usize) ||
        !check_assignments(i64.MAX, i64.MIN, 0i64, 1i64, 2i64, -1i64,
            i64.MIN, i64.MAX, -2i64, i64.MAX / 2i64, 64usize) {
        return 4
    }
    if !check_binary(i128.MAX, i128.MIN, 0i128, 1i128, 2i128, -1i128,
        i128.MIN, i128.MAX, -2i128, i128.MAX / 2i128) ||
        !check_unary(0i128, 1i128, i128.MIN, i128.MAX, -1i128) ||
        !check_shifts(1i128, 2i128, i128.MAX, i128.MAX / 2i128, 128usize) ||
        !check_assignments(i128.MAX, i128.MIN, 0i128, 1i128, 2i128, -1i128,
            i128.MIN, i128.MAX, -2i128, i128.MAX / 2i128, 128usize) {
        return 5
    }
    if !check_binary(isize.MAX, isize.MIN, 0isize, 1isize, 2isize, -1isize,
        isize.MIN, isize.MAX, -2isize, isize.MAX / 2isize) ||
        !check_unary(0isize, 1isize, isize.MIN, isize.MAX, -1isize) ||
        !check_shifts(1isize, 2isize, isize.MAX, isize.MAX / 2isize, 64usize) ||
        !check_assignments(isize.MAX, isize.MIN, 0isize, 1isize, 2isize, -1isize,
            isize.MIN, isize.MAX, -2isize, isize.MAX / 2isize,
            64usize) {
        return 6
    }

    if !check_binary(u8.MAX, 0u8, 0u8, 1u8, 2u8, u8.MAX,
        0u8, u8.MAX, u8.MAX - 1u8, u8.MAX / 2u8) ||
        !check_unary(0u8, 1u8, 0u8, u8.MAX, u8.MAX) ||
        !check_shifts(1u8, 2u8, u8.MAX, u8.MAX / 2u8, 8usize) ||
        !check_assignments(u8.MAX, 0u8, 0u8, 1u8, 2u8, u8.MAX,
            0u8, u8.MAX, u8.MAX - 1u8, u8.MAX / 2u8, 8usize) {
        return 7
    }
    if !check_binary(u16.MAX, 0u16, 0u16, 1u16, 2u16, u16.MAX,
        0u16, u16.MAX, u16.MAX - 1u16, u16.MAX / 2u16) ||
        !check_unary(0u16, 1u16, 0u16, u16.MAX, u16.MAX) ||
        !check_shifts(1u16, 2u16, u16.MAX, u16.MAX / 2u16, 16usize) ||
        !check_assignments(u16.MAX, 0u16, 0u16, 1u16, 2u16, u16.MAX,
            0u16, u16.MAX, u16.MAX - 1u16, u16.MAX / 2u16, 16usize) {
        return 8
    }
    if !check_binary(u32.MAX, 0u32, 0u32, 1u32, 2u32, u32.MAX,
        0u32, u32.MAX, u32.MAX - 1u32, u32.MAX / 2u32) ||
        !check_unary(0u32, 1u32, 0u32, u32.MAX, u32.MAX) ||
        !check_shifts(1u32, 2u32, u32.MAX, u32.MAX / 2u32, 32usize) ||
        !check_assignments(u32.MAX, 0u32, 0u32, 1u32, 2u32, u32.MAX,
            0u32, u32.MAX, u32.MAX - 1u32, u32.MAX / 2u32, 32usize) {
        return 9
    }
    if !check_binary(u64.MAX, 0u64, 0u64, 1u64, 2u64, u64.MAX,
        0u64, u64.MAX, u64.MAX - 1u64, u64.MAX / 2u64) ||
        !check_unary(0u64, 1u64, 0u64, u64.MAX, u64.MAX) ||
        !check_shifts(1u64, 2u64, u64.MAX, u64.MAX / 2u64, 64usize) ||
        !check_assignments(u64.MAX, 0u64, 0u64, 1u64, 2u64, u64.MAX,
            0u64, u64.MAX, u64.MAX - 1u64, u64.MAX / 2u64, 64usize) {
        return 10
    }
    if !check_binary(u128.MAX, 0u128, 0u128, 1u128, 2u128, u128.MAX,
        0u128, u128.MAX, u128.MAX - 1u128, u128.MAX / 2u128) ||
        !check_unary(0u128, 1u128, 0u128, u128.MAX, u128.MAX) ||
        !check_shifts(1u128, 2u128, u128.MAX, u128.MAX / 2u128, 128usize) ||
        !check_assignments(u128.MAX, 0u128, 0u128, 1u128, 2u128, u128.MAX,
            0u128, u128.MAX, u128.MAX - 1u128, u128.MAX / 2u128, 128usize) {
        return 11
    }
    if !check_binary(usize.MAX, 0usize, 0usize, 1usize, 2usize, usize.MAX,
        0usize, usize.MAX, usize.MAX - 1usize, usize.MAX / 2usize) ||
        !check_unary(0usize, 1usize, 0usize, usize.MAX, usize.MAX) ||
        !check_shifts(1usize, 2usize, usize.MAX, usize.MAX / 2usize, 64usize) ||
        !check_assignments(usize.MAX, 0usize, 0usize, 1usize, 2usize, usize.MAX,
            0usize, usize.MAX, usize.MAX - 1usize, usize.MAX / 2usize,
            64usize) {
        return 12
    }

    0
}
