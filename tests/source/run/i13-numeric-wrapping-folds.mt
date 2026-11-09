// profiles: debug release

import core.cmp.PartialEq
import core.default.Default
import core.iter
import core.iter.{ Product, Sum }
import core.num.Wrapping

fn sum_two<T: Sum>(take first: T, take second: T): T {
    iter.sum(iter.chain(iter.once(first), iter.once(second)))
}

fn product_two<T: Product>(take first: T, take second: T): T {
    iter.product(iter.chain(iter.once(first), iter.once(second)))
}

fn sum_empty<T: Sum>(): T { iter.sum(iter.empty<T>()) }
fn product_empty<T: Product>(): T { iter.product(iter.empty<T>()) }

fn default_is<T: Copy + Default + PartialEq>(expected: T): bool {
    let value = Wrapping<T>.(Default).default()
    value.value == expected
}

fn main(): i32 {
    if !default_is(0i8) || !default_is(0i16) || !default_is(0i32) ||
        !default_is(0i64) || !default_is(0i128) || !default_is(0isize) ||
        !default_is(0u8) || !default_is(0u16) || !default_is(0u32) ||
        !default_is(0u64) || !default_is(0u128) || !default_is(0usize) {
        return 1
    }

    if sum_two(Wrapping(i8.MAX), Wrapping(1i8)).value != i8.MIN ||
        product_two(Wrapping(i8.MAX), Wrapping(2i8)).value != -2i8 ||
        sum_empty<Wrapping<i8>>().value != 0i8 ||
        product_empty<Wrapping<i8>>().value != 1i8 {
        return 2
    }
    if sum_two(Wrapping(i16.MAX), Wrapping(1i16)).value != i16.MIN ||
        product_two(Wrapping(i16.MAX), Wrapping(2i16)).value != -2i16 ||
        sum_empty<Wrapping<i16>>().value != 0i16 ||
        product_empty<Wrapping<i16>>().value != 1i16 {
        return 3
    }
    if sum_two(Wrapping(i32.MAX), Wrapping(1i32)).value != i32.MIN ||
        product_two(Wrapping(i32.MAX), Wrapping(2i32)).value != -2i32 ||
        sum_empty<Wrapping<i32>>().value != 0i32 ||
        product_empty<Wrapping<i32>>().value != 1i32 {
        return 4
    }
    if sum_two(Wrapping(i64.MAX), Wrapping(1i64)).value != i64.MIN ||
        product_two(Wrapping(i64.MAX), Wrapping(2i64)).value != -2i64 ||
        sum_empty<Wrapping<i64>>().value != 0i64 ||
        product_empty<Wrapping<i64>>().value != 1i64 {
        return 5
    }
    if sum_two(Wrapping(i128.MAX), Wrapping(1i128)).value != i128.MIN ||
        product_two(Wrapping(i128.MAX), Wrapping(2i128)).value != -2i128 ||
        sum_empty<Wrapping<i128>>().value != 0i128 ||
        product_empty<Wrapping<i128>>().value != 1i128 {
        return 6
    }
    if sum_two(Wrapping(isize.MAX), Wrapping(1isize)).value != isize.MIN ||
        product_two(Wrapping(isize.MAX), Wrapping(2isize)).value != -2isize ||
        sum_empty<Wrapping<isize>>().value != 0isize ||
        product_empty<Wrapping<isize>>().value != 1isize {
        return 7
    }

    if sum_two(Wrapping(u8.MAX), Wrapping(1u8)).value != 0u8 ||
        product_two(Wrapping(u8.MAX), Wrapping(2u8)).value != u8.MAX - 1u8 ||
        sum_empty<Wrapping<u8>>().value != 0u8 ||
        product_empty<Wrapping<u8>>().value != 1u8 {
        return 8
    }
    if sum_two(Wrapping(u16.MAX), Wrapping(1u16)).value != 0u16 ||
        product_two(Wrapping(u16.MAX), Wrapping(2u16)).value != u16.MAX - 1u16 ||
        sum_empty<Wrapping<u16>>().value != 0u16 ||
        product_empty<Wrapping<u16>>().value != 1u16 {
        return 9
    }
    if sum_two(Wrapping(u32.MAX), Wrapping(1u32)).value != 0u32 ||
        product_two(Wrapping(u32.MAX), Wrapping(2u32)).value != u32.MAX - 1u32 ||
        sum_empty<Wrapping<u32>>().value != 0u32 ||
        product_empty<Wrapping<u32>>().value != 1u32 {
        return 10
    }
    if sum_two(Wrapping(u64.MAX), Wrapping(1u64)).value != 0u64 ||
        product_two(Wrapping(u64.MAX), Wrapping(2u64)).value != u64.MAX - 1u64 ||
        sum_empty<Wrapping<u64>>().value != 0u64 ||
        product_empty<Wrapping<u64>>().value != 1u64 {
        return 11
    }
    if sum_two(Wrapping(u128.MAX), Wrapping(1u128)).value != 0u128 ||
        product_two(Wrapping(u128.MAX), Wrapping(2u128)).value != u128.MAX - 1u128 ||
        sum_empty<Wrapping<u128>>().value != 0u128 ||
        product_empty<Wrapping<u128>>().value != 1u128 {
        return 12
    }
    if sum_two(Wrapping(usize.MAX), Wrapping(1usize)).value != 0usize ||
        product_two(Wrapping(usize.MAX), Wrapping(2usize)).value != usize.MAX - 1usize ||
        sum_empty<Wrapping<usize>>().value != 0usize ||
        product_empty<Wrapping<usize>>().value != 1usize {
        return 13
    }

    0
}
