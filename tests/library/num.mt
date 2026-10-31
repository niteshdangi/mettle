import core.num
import core.num.IntErrorKind
import core.option

fn kind<T: num.FromText>(text: read core.text.Text): IntErrorKind? {
    match capture num.parse<T>(text) { success(v) => none, failure(e) => present(e.kind) }
}
fn main(): i32 {
    match capture num.parse<i32>("123") { success(v) => { if v != 123 { return 1 } }, failure(e) => { return 2 } }
    match capture num.parse<i32>("-2147483648") { success(v) => { if v != -2147483648 { return 3 } }, failure(e) => { return 4 } }
    match capture num.parse<i64>("-9223372036854775808") { success(v) => { if v != -9223372036854775807i64 - 1i64 { return 5 } }, failure(e) => { return 6 } }
    match capture num.parse<u64>("18446744073709551615") { success(v) => { if v != 18446744073709551615u64 { return 7 } }, failure(e) => { return 8 } }
    match capture num.parse_radix<u8>("ff", 16u32) { success(v) => { if v != 255u8 { return 9 } }, failure(e) => { return 10 } }
    match capture num.parse_radix<i32>("-1010", 2u32) { success(v) => { if v != -10 { return 11 } }, failure(e) => { return 12 } }
    match capture num.parse<i32>("+7") { success(v) => { if v != 7 { return 13 } }, failure(e) => { return 14 } }
    match kind<i32>("") { present(k) => { if k != IntErrorKind.Empty { return 15 } }, none => { return 16 } }
    match kind<i32>("12a") { present(k) => { if k != IntErrorKind.InvalidDigit { return 17 } }, none => { return 18 } }
    match kind<i32>("-") { present(k) => { if k != IntErrorKind.InvalidDigit { return 19 } }, none => { return 20 } }
    match kind<u8>("256") { present(k) => { if k != IntErrorKind.PosOverflow { return 21 } }, none => { return 22 } }
    match kind<i8>("-129") { present(k) => { if k != IntErrorKind.NegOverflow { return 23 } }, none => { return 24 } }
    match kind<u8>("-1") { present(k) => { if k != IntErrorKind.InvalidDigit { return 25 } }, none => { return 26 } }
    match kind<u64>("18446744073709551616") { present(k) => { if k != IntErrorKind.PosOverflow { return 27 } }, none => { return 28 } }
    match kind<i32>("99999999999999999999999x") { present(k) => { if k != IntErrorKind.InvalidDigit { return 29 } }, none => { return 30 } }
    match kind<i32>("1") { present(k) => { return 31 }, none => {} }
    match capture num.parse<i128>("-170141183460469231731687303715884105728") {
        success(v) => { if v != -170141183460469231731687303715884105728i128 { return 32 } },
        failure(e) => { return 33 }
    }
    match capture num.parse<i128>("170141183460469231731687303715884105727") {
        success(v) => { if v != 170141183460469231731687303715884105727i128 { return 34 } },
        failure(e) => { return 35 }
    }
    match capture num.parse_radix<u128>("ffffffffffffffffffffffffffffffff", 16u32) {
        success(v) => { if v != 340282366920938463463374607431768211455u128 { return 36 } },
        failure(e) => { return 37 }
    }
    match kind<u128>("340282366920938463463374607431768211456") {
        present(k) => { if k != IntErrorKind.PosOverflow { return 38 } },
        none => { return 39 }
    }
    match kind<i128>("-170141183460469231731687303715884105729") {
        present(k) => { if k != IntErrorKind.NegOverflow { return 40 } },
        none => { return 41 }
    }
    match kind<u128>("340282366920938463463374607431768211456x") {
        present(k) => { if k != IntErrorKind.InvalidDigit { return 42 } },
        none => { return 43 }
    }
    match capture num.parse<i8>("-128") { success(v) => { if v != -128i8 { return 44 } }, failure(e) => { return 45 } }
    match capture num.parse<i16>("32767") { success(v) => { if v != 32767i16 { return 46 } }, failure(e) => { return 47 } }
    match capture num.parse<u16>("65535") { success(v) => { if v != 65535u16 { return 48 } }, failure(e) => { return 49 } }
    match capture num.parse<u32>("4294967295") { success(v) => { if v != 4294967295u32 { return 50 } }, failure(e) => { return 51 } }
    match capture num.parse<isize>("-9223372036854775808") { success(v) => { if v != -9223372036854775808isize { return 52 } }, failure(e) => { return 53 } }
    match capture num.parse<usize>("18446744073709551615") { success(v) => { if v != 18446744073709551615usize { return 54 } }, failure(e) => { return 55 } }
    0
}
