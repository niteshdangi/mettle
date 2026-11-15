// profiles: debug release
import core.iter
import core.iter.{ Iterator, Sum, Product }

type Total { value: i32 }

extend<region r> Total implements Sum<read i32 from r> {
    static fn zero(): Total { Total(0) }
    fn plus(take other: read i32 from r): Total { Total(self.value + *other) }
}

extend<region r> Total implements Product<read i32 from r> {
    static fn one(): Total { Total(1) }
    fn times(take other: read i32 from r): Total { Total(self.value * *other) }
}

fn main(): i32 {
    var values = [2, 3]
    let total = values.iter().sum<Total>()
    let multiplied: Total = values.iter().product()
    values[0usize] = 9
    assert(total.value == 5 && multiplied.value == 6,
        "borrowed inputs produce independent owned results")
    assert(iter.sum(iter.once(2).chain(iter.once(3))) == 5,
        "owned sum keeps inferred output")
    assert(iter.product(iter.once(2).chain(iter.once(3))) == 6,
        "owned product keeps inferred output")
    let i8s = [2i8, 3i8]
    let i16s = [2i16, 3i16]
    let i32s = [2i32, 3i32]
    let i64s = [2i64, 3i64]
    let i128s = [2i128, 3i128]
    let isizes = [2isize, 3isize]
    let u8s = [2u8, 3u8]
    let u16s = [2u16, 3u16]
    let u32s = [2u32, 3u32]
    let u64s = [2u64, 3u64]
    let u128s = [2u128, 3u128]
    let usizes = [2usize, 3usize]
    assert(
        i8s.iter().sum<i8>() == 5i8 && i8s.iter().product<i8>() == 6i8 &&
        i16s.iter().sum<i16>() == 5i16 && i16s.iter().product<i16>() == 6i16 &&
        i32s.iter().sum<i32>() == 5i32 && i32s.iter().product<i32>() == 6i32 &&
        i64s.iter().sum<i64>() == 5i64 && i64s.iter().product<i64>() == 6i64 &&
        i128s.iter().sum<i128>() == 5i128 && i128s.iter().product<i128>() == 6i128 &&
        isizes.iter().sum<isize>() == 5isize && isizes.iter().product<isize>() == 6isize &&
        u8s.iter().sum<u8>() == 5u8 && u8s.iter().product<u8>() == 6u8 &&
        u16s.iter().sum<u16>() == 5u16 && u16s.iter().product<u16>() == 6u16 &&
        u32s.iter().sum<u32>() == 5u32 && u32s.iter().product<u32>() == 6u32 &&
        u64s.iter().sum<u64>() == 5u64 && u64s.iter().product<u64>() == 6u64 &&
        u128s.iter().sum<u128>() == 5u128 && u128s.iter().product<u128>() == 6u128 &&
        usizes.iter().sum<usize>() == 5usize && usizes.iter().product<usize>() == 6usize,
        "borrowed integer folds preserve arithmetic identities"
    )
    0
}
