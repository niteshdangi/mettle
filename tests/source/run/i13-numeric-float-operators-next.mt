// expect-exit: 0
// profiles: debug release

import core.float
import core.ops.{Add, AddAssign, Div, DivAssign, Mul, MulAssign}
import core.ops.{Neg, Rem, RemAssign, Sub, SubAssign}

fn trait_add<L: Copy, R: Copy>(left: L, rhs: R): L.(Add<R>).Output
where L: Add<R>
{
    L.(Add<R>).add(left, rhs)
}

fn trait_sub<L: Copy, R: Copy>(left: L, rhs: R): L.(Sub<R>).Output
where L: Sub<R>
{
    L.(Sub<R>).sub(left, rhs)
}

fn trait_mul<L: Copy, R: Copy>(left: L, rhs: R): L.(Mul<R>).Output
where L: Mul<R>
{
    L.(Mul<R>).mul(left, rhs)
}

fn trait_div<L: Copy, R: Copy>(left: L, rhs: R): L.(Div<R>).Output
where L: Div<R>
{
    L.(Div<R>).div(left, rhs)
}

fn trait_rem<L: Copy, R: Copy>(left: L, rhs: R): L.(Rem<R>).Output
where L: Rem<R>
{
    L.(Rem<R>).rem(left, rhs)
}

fn trait_neg<L: Copy>(value: L): L.(Neg).Output
where L: Neg
{
    L.(Neg).neg(value)
}

fn trait_add_assign<L, R: Copy>(mut value: L, rhs: R): Unit
where L: AddAssign<R>
{
    L.(AddAssign<R>).add_assign(mut value, rhs)
}

fn trait_sub_assign<L, R: Copy>(mut value: L, rhs: R): Unit
where L: SubAssign<R>
{
    L.(SubAssign<R>).sub_assign(mut value, rhs)
}

fn trait_mul_assign<L, R: Copy>(mut value: L, rhs: R): Unit
where L: MulAssign<R>
{
    L.(MulAssign<R>).mul_assign(mut value, rhs)
}

fn trait_div_assign<L, R: Copy>(mut value: L, rhs: R): Unit
where L: DivAssign<R>
{
    L.(DivAssign<R>).div_assign(mut value, rhs)
}

fn trait_rem_assign<L, R: Copy>(mut value: L, rhs: R): Unit
where L: RemAssign<R>
{
    L.(RemAssign<R>).rem_assign(mut value, rhs)
}

fn check_f32(): bool {
    let left = 7.0f32
    let right = 2.0f32
    if trait_add(left, right) != 9.0f32 ||
       trait_add(read left, right) != 9.0f32 ||
       trait_add(left, read right) != 9.0f32 ||
       trait_add(read left, read right) != 9.0f32 {
        return false
    }
    if trait_sub(left, right) != 5.0f32 ||
       trait_sub(read left, right) != 5.0f32 ||
       trait_sub(left, read right) != 5.0f32 ||
       trait_sub(read left, read right) != 5.0f32 {
        return false
    }
    if trait_mul(left, right) != 14.0f32 ||
       trait_mul(read left, right) != 14.0f32 ||
       trait_mul(left, read right) != 14.0f32 ||
       trait_mul(read left, read right) != 14.0f32 {
        return false
    }
    if trait_div(left, right) != 3.5f32 ||
       trait_div(read left, right) != 3.5f32 ||
       trait_div(left, read right) != 3.5f32 ||
       trait_div(read left, read right) != 3.5f32 {
        return false
    }
    if trait_rem(left, right) != 1.0f32 ||
       trait_rem(read left, right) != 1.0f32 ||
       trait_rem(left, read right) != 1.0f32 ||
       trait_rem(read left, read right) != 1.0f32 {
        return false
    }

    let negative_zero = -0.0f32
    let nan = f32.from_bits(0x7fc12345u32)
    if trait_add(negative_zero, negative_zero).to_bits() != 0x80000000u32 ||
       trait_sub(negative_zero, 0.0f32).to_bits() != 0x80000000u32 ||
       trait_mul(negative_zero, 2.0f32).to_bits() != 0x80000000u32 ||
       trait_div(negative_zero, 2.0f32).to_bits() != 0x80000000u32 ||
       !trait_add(nan, 1.0f32).is_nan() ||
       !trait_div(1.0f32, 0.0f32).is_infinite() ||
       !trait_div(0.0f32, 0.0f32).is_nan() ||
       !trait_rem(1.0f32, 0.0f32).is_nan() {
        return false
    }

    var add_owned = left
    trait_add_assign(mut add_owned, right)
    var add_read = left
    trait_add_assign(mut add_read, read right)
    if add_owned != 9.0f32 || add_read != 9.0f32 { return false }

    var sub_owned = left
    trait_sub_assign(mut sub_owned, right)
    var sub_read = left
    trait_sub_assign(mut sub_read, read right)
    if sub_owned != 5.0f32 || sub_read != 5.0f32 { return false }

    var mul_owned = left
    trait_mul_assign(mut mul_owned, right)
    var mul_read = left
    trait_mul_assign(mut mul_read, read right)
    if mul_owned != 14.0f32 || mul_read != 14.0f32 { return false }

    var div_owned = left
    trait_div_assign(mut div_owned, right)
    var div_read = left
    trait_div_assign(mut div_read, read right)
    if div_owned != 3.5f32 || div_read != 3.5f32 { return false }

    var rem_owned = left
    trait_rem_assign(mut rem_owned, right)
    var rem_read = left
    trait_rem_assign(mut rem_read, read right)
    if rem_owned != 1.0f32 || rem_read != 1.0f32 { return false }

    trait_neg(negative_zero).to_bits() == 0u32 &&
        trait_neg(read negative_zero).to_bits() == 0u32 &&
        trait_neg(nan).is_nan() &&
        trait_neg(read nan).is_nan()
}

fn check_f64(): bool {
    let left = 7.0f64
    let right = 2.0f64
    if trait_add(left, right) != 9.0f64 ||
       trait_add(read left, right) != 9.0f64 ||
       trait_add(left, read right) != 9.0f64 ||
       trait_add(read left, read right) != 9.0f64 {
        return false
    }
    if trait_sub(left, right) != 5.0f64 ||
       trait_sub(read left, right) != 5.0f64 ||
       trait_sub(left, read right) != 5.0f64 ||
       trait_sub(read left, read right) != 5.0f64 {
        return false
    }
    if trait_mul(left, right) != 14.0f64 ||
       trait_mul(read left, right) != 14.0f64 ||
       trait_mul(left, read right) != 14.0f64 ||
       trait_mul(read left, read right) != 14.0f64 {
        return false
    }
    if trait_div(left, right) != 3.5f64 ||
       trait_div(read left, right) != 3.5f64 ||
       trait_div(left, read right) != 3.5f64 ||
       trait_div(read left, read right) != 3.5f64 {
        return false
    }
    if trait_rem(left, right) != 1.0f64 ||
       trait_rem(read left, right) != 1.0f64 ||
       trait_rem(left, read right) != 1.0f64 ||
       trait_rem(read left, read right) != 1.0f64 {
        return false
    }

    let negative_zero = -0.0f64
    let nan = f64.from_bits(0x7ff8123456789abcu64)
    if trait_add(negative_zero, negative_zero).to_bits() != 0x8000000000000000u64 ||
       trait_sub(negative_zero, 0.0f64).to_bits() != 0x8000000000000000u64 ||
       trait_mul(negative_zero, 2.0f64).to_bits() != 0x8000000000000000u64 ||
       trait_div(negative_zero, 2.0f64).to_bits() != 0x8000000000000000u64 ||
       !trait_add(nan, 1.0f64).is_nan() ||
       !trait_div(1.0f64, 0.0f64).is_infinite() ||
       !trait_div(0.0f64, 0.0f64).is_nan() ||
       !trait_rem(1.0f64, 0.0f64).is_nan() {
        return false
    }

    var add_owned = left
    trait_add_assign(mut add_owned, right)
    var add_read = left
    trait_add_assign(mut add_read, read right)
    if add_owned != 9.0f64 || add_read != 9.0f64 { return false }

    var sub_owned = left
    trait_sub_assign(mut sub_owned, right)
    var sub_read = left
    trait_sub_assign(mut sub_read, read right)
    if sub_owned != 5.0f64 || sub_read != 5.0f64 { return false }

    var mul_owned = left
    trait_mul_assign(mut mul_owned, right)
    var mul_read = left
    trait_mul_assign(mut mul_read, read right)
    if mul_owned != 14.0f64 || mul_read != 14.0f64 { return false }

    var div_owned = left
    trait_div_assign(mut div_owned, right)
    var div_read = left
    trait_div_assign(mut div_read, read right)
    if div_owned != 3.5f64 || div_read != 3.5f64 { return false }

    var rem_owned = left
    trait_rem_assign(mut rem_owned, right)
    var rem_read = left
    trait_rem_assign(mut rem_read, read right)
    if rem_owned != 1.0f64 || rem_read != 1.0f64 { return false }

    trait_neg(negative_zero).to_bits() == 0u64 &&
        trait_neg(read negative_zero).to_bits() == 0u64 &&
        trait_neg(nan).is_nan() &&
        trait_neg(read nan).is_nan()
}

fn main(): i32 {
    if !check_f32() { return 1 }
    if !check_f64() { return 2 }
    0
}
