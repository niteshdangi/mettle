// profiles: debug release

import core.iter.{ Iterator, Product, Sum }
import core.num.Wrapping

fn main(): i32 {
    let empty_i8: [Wrapping<i8>; 0] = []
    if empty_i8.iter().sum<Wrapping<i8>>().value != 0i8 ||
        empty_i8.iter().product<Wrapping<i8>>().value != 1i8 {
        return 1
    }
    let values_i8 = [Wrapping(i8.MAX), Wrapping(2i8)]
    let sum_i8 = values_i8.iter().sum<Wrapping<i8>>()
    let product_i8: Wrapping<i8> = values_i8.iter().product()
    let sum_again_i8 = values_i8.iter().sum<Wrapping<i8>>()
    let product_again_i8: Wrapping<i8> = values_i8.iter().product()
    if sum_i8.value != i8.MIN + 1i8 || product_i8.value != -2i8 ||
        sum_again_i8.value != sum_i8.value ||
        product_again_i8.value != product_i8.value ||
        values_i8[0usize].value != i8.MAX || values_i8[1usize].value != 2i8 {
        return 2
    }

    let empty_i16: [Wrapping<i16>; 0] = []
    if empty_i16.iter().sum<Wrapping<i16>>().value != 0i16 ||
        empty_i16.iter().product<Wrapping<i16>>().value != 1i16 {
        return 3
    }
    let values_i16 = [Wrapping(i16.MAX), Wrapping(2i16)]
    let sum_i16 = values_i16.iter().sum<Wrapping<i16>>()
    let product_i16: Wrapping<i16> = values_i16.iter().product()
    let sum_again_i16 = values_i16.iter().sum<Wrapping<i16>>()
    let product_again_i16: Wrapping<i16> = values_i16.iter().product()
    if sum_i16.value != i16.MIN + 1i16 || product_i16.value != -2i16 ||
        sum_again_i16.value != sum_i16.value ||
        product_again_i16.value != product_i16.value ||
        values_i16[0usize].value != i16.MAX || values_i16[1usize].value != 2i16 {
        return 4
    }

    let empty_i32: [Wrapping<i32>; 0] = []
    if empty_i32.iter().sum<Wrapping<i32>>().value != 0i32 ||
        empty_i32.iter().product<Wrapping<i32>>().value != 1i32 {
        return 5
    }
    let values_i32 = [Wrapping(i32.MAX), Wrapping(2i32)]
    let sum_i32 = values_i32.iter().sum<Wrapping<i32>>()
    let product_i32: Wrapping<i32> = values_i32.iter().product()
    let sum_again_i32 = values_i32.iter().sum<Wrapping<i32>>()
    let product_again_i32: Wrapping<i32> = values_i32.iter().product()
    if sum_i32.value != i32.MIN + 1i32 || product_i32.value != -2i32 ||
        sum_again_i32.value != sum_i32.value ||
        product_again_i32.value != product_i32.value ||
        values_i32[0usize].value != i32.MAX || values_i32[1usize].value != 2i32 {
        return 6
    }

    let empty_i64: [Wrapping<i64>; 0] = []
    if empty_i64.iter().sum<Wrapping<i64>>().value != 0i64 ||
        empty_i64.iter().product<Wrapping<i64>>().value != 1i64 {
        return 7
    }
    let values_i64 = [Wrapping(i64.MAX), Wrapping(2i64)]
    let sum_i64 = values_i64.iter().sum<Wrapping<i64>>()
    let product_i64: Wrapping<i64> = values_i64.iter().product()
    let sum_again_i64 = values_i64.iter().sum<Wrapping<i64>>()
    let product_again_i64: Wrapping<i64> = values_i64.iter().product()
    if sum_i64.value != i64.MIN + 1i64 || product_i64.value != -2i64 ||
        sum_again_i64.value != sum_i64.value ||
        product_again_i64.value != product_i64.value ||
        values_i64[0usize].value != i64.MAX || values_i64[1usize].value != 2i64 {
        return 8
    }

    let empty_i128: [Wrapping<i128>; 0] = []
    if empty_i128.iter().sum<Wrapping<i128>>().value != 0i128 ||
        empty_i128.iter().product<Wrapping<i128>>().value != 1i128 {
        return 9
    }
    let values_i128 = [Wrapping(i128.MAX), Wrapping(2i128)]
    let sum_i128 = values_i128.iter().sum<Wrapping<i128>>()
    let product_i128: Wrapping<i128> = values_i128.iter().product()
    let sum_again_i128 = values_i128.iter().sum<Wrapping<i128>>()
    let product_again_i128: Wrapping<i128> = values_i128.iter().product()
    if sum_i128.value != i128.MIN + 1i128 || product_i128.value != -2i128 ||
        sum_again_i128.value != sum_i128.value ||
        product_again_i128.value != product_i128.value ||
        values_i128[0usize].value != i128.MAX || values_i128[1usize].value != 2i128 {
        return 10
    }

    let empty_isize: [Wrapping<isize>; 0] = []
    if empty_isize.iter().sum<Wrapping<isize>>().value != 0isize ||
        empty_isize.iter().product<Wrapping<isize>>().value != 1isize {
        return 11
    }
    let values_isize = [Wrapping(isize.MAX), Wrapping(2isize)]
    let sum_isize = values_isize.iter().sum<Wrapping<isize>>()
    let product_isize: Wrapping<isize> = values_isize.iter().product()
    let sum_again_isize = values_isize.iter().sum<Wrapping<isize>>()
    let product_again_isize: Wrapping<isize> = values_isize.iter().product()
    if sum_isize.value != isize.MIN + 1isize || product_isize.value != -2isize ||
        sum_again_isize.value != sum_isize.value ||
        product_again_isize.value != product_isize.value ||
        values_isize[0usize].value != isize.MAX || values_isize[1usize].value != 2isize {
        return 12
    }

    let empty_u8: [Wrapping<u8>; 0] = []
    if empty_u8.iter().sum<Wrapping<u8>>().value != 0u8 ||
        empty_u8.iter().product<Wrapping<u8>>().value != 1u8 {
        return 13
    }
    let values_u8 = [Wrapping(u8.MAX), Wrapping(2u8)]
    let sum_u8 = values_u8.iter().sum<Wrapping<u8>>()
    let product_u8: Wrapping<u8> = values_u8.iter().product()
    let sum_again_u8 = values_u8.iter().sum<Wrapping<u8>>()
    let product_again_u8: Wrapping<u8> = values_u8.iter().product()
    if sum_u8.value != 1u8 || product_u8.value != u8.MAX - 1u8 ||
        sum_again_u8.value != sum_u8.value ||
        product_again_u8.value != product_u8.value ||
        values_u8[0usize].value != u8.MAX || values_u8[1usize].value != 2u8 {
        return 14
    }

    let empty_u16: [Wrapping<u16>; 0] = []
    if empty_u16.iter().sum<Wrapping<u16>>().value != 0u16 ||
        empty_u16.iter().product<Wrapping<u16>>().value != 1u16 {
        return 15
    }
    let values_u16 = [Wrapping(u16.MAX), Wrapping(2u16)]
    let sum_u16 = values_u16.iter().sum<Wrapping<u16>>()
    let product_u16: Wrapping<u16> = values_u16.iter().product()
    let sum_again_u16 = values_u16.iter().sum<Wrapping<u16>>()
    let product_again_u16: Wrapping<u16> = values_u16.iter().product()
    if sum_u16.value != 1u16 || product_u16.value != u16.MAX - 1u16 ||
        sum_again_u16.value != sum_u16.value ||
        product_again_u16.value != product_u16.value ||
        values_u16[0usize].value != u16.MAX || values_u16[1usize].value != 2u16 {
        return 16
    }

    let empty_u32: [Wrapping<u32>; 0] = []
    if empty_u32.iter().sum<Wrapping<u32>>().value != 0u32 ||
        empty_u32.iter().product<Wrapping<u32>>().value != 1u32 {
        return 17
    }
    let values_u32 = [Wrapping(u32.MAX), Wrapping(2u32)]
    let sum_u32 = values_u32.iter().sum<Wrapping<u32>>()
    let product_u32: Wrapping<u32> = values_u32.iter().product()
    let sum_again_u32 = values_u32.iter().sum<Wrapping<u32>>()
    let product_again_u32: Wrapping<u32> = values_u32.iter().product()
    if sum_u32.value != 1u32 || product_u32.value != u32.MAX - 1u32 ||
        sum_again_u32.value != sum_u32.value ||
        product_again_u32.value != product_u32.value ||
        values_u32[0usize].value != u32.MAX || values_u32[1usize].value != 2u32 {
        return 18
    }

    let empty_u64: [Wrapping<u64>; 0] = []
    if empty_u64.iter().sum<Wrapping<u64>>().value != 0u64 ||
        empty_u64.iter().product<Wrapping<u64>>().value != 1u64 {
        return 19
    }
    let values_u64 = [Wrapping(u64.MAX), Wrapping(2u64)]
    let sum_u64 = values_u64.iter().sum<Wrapping<u64>>()
    let product_u64: Wrapping<u64> = values_u64.iter().product()
    let sum_again_u64 = values_u64.iter().sum<Wrapping<u64>>()
    let product_again_u64: Wrapping<u64> = values_u64.iter().product()
    if sum_u64.value != 1u64 || product_u64.value != u64.MAX - 1u64 ||
        sum_again_u64.value != sum_u64.value ||
        product_again_u64.value != product_u64.value ||
        values_u64[0usize].value != u64.MAX || values_u64[1usize].value != 2u64 {
        return 20
    }

    let empty_u128: [Wrapping<u128>; 0] = []
    if empty_u128.iter().sum<Wrapping<u128>>().value != 0u128 ||
        empty_u128.iter().product<Wrapping<u128>>().value != 1u128 {
        return 21
    }
    let values_u128 = [Wrapping(u128.MAX), Wrapping(2u128)]
    let sum_u128 = values_u128.iter().sum<Wrapping<u128>>()
    let product_u128: Wrapping<u128> = values_u128.iter().product()
    let sum_again_u128 = values_u128.iter().sum<Wrapping<u128>>()
    let product_again_u128: Wrapping<u128> = values_u128.iter().product()
    if sum_u128.value != 1u128 || product_u128.value != u128.MAX - 1u128 ||
        sum_again_u128.value != sum_u128.value ||
        product_again_u128.value != product_u128.value ||
        values_u128[0usize].value != u128.MAX || values_u128[1usize].value != 2u128 {
        return 22
    }

    let empty_usize: [Wrapping<usize>; 0] = []
    if empty_usize.iter().sum<Wrapping<usize>>().value != 0usize ||
        empty_usize.iter().product<Wrapping<usize>>().value != 1usize {
        return 23
    }
    let values_usize = [Wrapping(usize.MAX), Wrapping(2usize)]
    let sum_usize = values_usize.iter().sum<Wrapping<usize>>()
    let product_usize: Wrapping<usize> = values_usize.iter().product()
    let sum_again_usize = values_usize.iter().sum<Wrapping<usize>>()
    let product_again_usize: Wrapping<usize> = values_usize.iter().product()
    if sum_usize.value != 1usize ||
        product_usize.value != usize.MAX - 1usize ||
        sum_again_usize.value != sum_usize.value ||
        product_again_usize.value != product_usize.value ||
        values_usize[0usize].value != usize.MAX || values_usize[1usize].value != 2usize {
        return 24
    }

    0
}
