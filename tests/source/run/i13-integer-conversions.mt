import core.convert
import core.convert.From
import core.convert.TryFrom
import core.convert.TryInto
import core.num
import core.num.TryFromIntError

fn main(): i32 {
    if u16.(From<u8>).`from`(200u8) != 200u16 { return 1 }
    if i16.(From<u8>).`from`(255u8) != 255i16 { return 2 }
    if i64.(From<i8>).`from`(-5i8) != -5i64 { return 3 }
    if usize.(From<u16>).`from`(65535u16) != 65535usize { return 4 }
    if isize.(From<u8>).`from`(9u8) != 9isize { return 5 }
    if u128.(From<u64>).`from`(18446744073709551615u64) != 18446744073709551615u128 { return 6 }
    let widened: u32 = 77u8.into()
    if widened != 77u32 { return 7 }

    match u8.(TryFrom<i32>).try_from(255i32) {
        success(value) => { if value != 255u8 { return 8 } },
        failure(_) => { return 8 }
    }
    match u8.(TryFrom<i32>).try_from(256i32) {
        success(_) => { return 9 },
        failure(error) => { if error != TryFromIntError() { return 9 } }
    }
    match u8.(TryFrom<i32>).try_from(-1i32) {
        success(_) => { return 10 },
        failure(_) => {}
    }
    match i8.(TryFrom<u8>).try_from(128u8) {
        success(_) => { return 11 },
        failure(_) => {}
    }
    match i8.(TryFrom<u8>).try_from(127u8) {
        success(value) => { if value != 127i8 { return 12 } },
        failure(_) => { return 12 }
    }
    match u64.(TryFrom<i128>).try_from(-1i128) {
        success(_) => { return 13 },
        failure(_) => {}
    }
    match i128.(TryFrom<u128>).try_from(170141183460469231731687303715884105727u128) {
        success(value) => { if value != 170141183460469231731687303715884105727i128 { return 14 } },
        failure(_) => { return 14 }
    }
    match i128.(TryFrom<u128>).try_from(170141183460469231731687303715884105728u128) {
        success(_) => { return 15 },
        failure(_) => {}
    }
    match usize.(TryFrom<u32>).try_from(4000000000u32) {
        success(value) => { if value != 4000000000usize { return 16 } },
        failure(_) => { return 16 }
    }
    match u16.(TryFrom<usize>).try_from(65536usize) {
        success(_) => { return 17 },
        failure(_) => {}
    }
    match u32.(TryFrom<u16>).try_from(65535u16) {
        success(value) => { if value != 65535u32 { return 18 } },
        failure(_) => { return 18 }
    }
    let narrowed: (u8 throws TryFromIntError) = u32.(TryInto<u8>).try_into(300u32)
    match narrowed {
        success(_) => { return 19 },
        failure(_) => {}
    }
    0
}
