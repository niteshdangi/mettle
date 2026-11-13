// profiles: debug release
// bool, char, u8 and float primitive operations and per-type constants:
// bool::then/then_present/ok_or/ok_or_else, char::decode_utf16, u8::escape_ascii
// and the bounds of every numeric primitive. Expected values are computed
// independently.
import core.option
import core.num
import core.char.{decode_utf16, DecodeUtf16Error}
import core.iter.Iterator

// A fixed sequence of code units for decoding.
type Units { data: [u16; 6]; length: usize; index: usize }
extend Units implements Iterator {
    type Item = u16
    mut fn next(): u16? {
        if self.index >= self.length { return none }
        let value = self.data[self.index]
        self.index += 1usize
        present(value)
    }
}

fn units(data: [u16; 6], length: usize): Units { Units(data, length, 0usize) }

fn ok_status<E>(result: (Outcome<Unit, E>)): bool {
    match result { success(_) => true, failure(_) => false }
}

fn error_code(result: (Outcome<Unit, i32>)): i32 {
    match result { success(_) => 0, failure(code) => code }
}

fn bool_operations(): i32 {
    if true.then(fn(): i32 { 7 }).unwrap() != 7 { return 1 }
    if false.then(fn(): i32 { 7 }).is_present() { return 2 }
    if true.then_present(7).unwrap() != 7 || false.then_present(7).is_present() { return 3 }
    if !ok_status(true.ok_or(9i32)) || ok_status(false.ok_or(9i32)) { return 4 }
    if error_code(false.ok_or(9i32)) != 9 { return 5 }
    if !ok_status(true.ok_or_else(fn(): i32 { 9 })) { return 6 }
    if error_code(false.ok_or_else(fn(): i32 { 9 })) != 9 { return 7 }
    0
}

fn scalar_or_code(item: (Outcome<char, DecodeUtf16Error>)?): i32 {
    match item {
        present(result) => match result {
            success(scalar) => scalar as u32 as i32,
            failure(error) => 0 - (error.unpaired_surrogate() as i32)
        },
        none => -1000000
    }
}

fn decode_operations(): i32 {
    var decoded = decode_utf16(units([0xd83du16, 0xde00u16, 0x61u16, 0xd800u16, 0x62u16, 0xdc00u16], 6usize))
    if scalar_or_code(decoded.next()) != 0x1f600 { return 10 }
    if scalar_or_code(decoded.next()) != 0x61 { return 11 }
    if scalar_or_code(decoded.next()) != -0xd800 { return 12 }
    if scalar_or_code(decoded.next()) != 0x62 { return 13 }
    if scalar_or_code(decoded.next()) != -0xdc00 { return 14 }
    if scalar_or_code(decoded.next()) != -1000000 { return 15 }

    var trailing = decode_utf16(units([0xd800u16, 0u16, 0u16, 0u16, 0u16, 0u16], 1usize))
    if scalar_or_code(trailing.next()) != -0xd800 || scalar_or_code(trailing.next()) != -1000000 { return 16 }

    var before_plain = decode_utf16(units([0xd800u16, 0x61u16, 0u16, 0u16, 0u16, 0u16], 2usize))
    if scalar_or_code(before_plain.next()) != -0xd800 || scalar_or_code(before_plain.next()) != 0x61 { return 17 }
    0
}

fn escape_is(byte: u8, expected: [u8; 4], length: usize): bool {
    var escape = byte.escape_ascii()
    var produced = [0u8; 4]
    var count = 0usize
    while true {
        match escape.next() {
            present(value) => {
                produced[count] = value
                count += 1usize
            },
            none => { break }
        }
    }
    if count != length { return false }
    var index = 0usize
    while index < length {
        if produced[index] != expected[index] { return false }
        index += 1usize
    }
    true
}

fn escape_operations(): i32 {
    if !escape_is(0x41u8, [0x41u8, 0u8, 0u8, 0u8], 1usize) { return 20 }
    if !escape_is(0x0au8, [0x5cu8, 0x6eu8, 0u8, 0u8], 2usize) { return 21 }
    if !escape_is(0x09u8, [0x5cu8, 0x74u8, 0u8, 0u8], 2usize) { return 22 }
    if !escape_is(0x0du8, [0x5cu8, 0x72u8, 0u8, 0u8], 2usize) { return 23 }
    if !escape_is(0x5cu8, [0x5cu8, 0x5cu8, 0u8, 0u8], 2usize) { return 24 }
    if !escape_is(0x27u8, [0x5cu8, 0x27u8, 0u8, 0u8], 2usize) { return 25 }
    if !escape_is(0x22u8, [0x5cu8, 0x22u8, 0u8, 0u8], 2usize) { return 26 }
    if !escape_is(0x00u8, [0x5cu8, 0x78u8, 0x30u8, 0x30u8], 4usize) { return 27 }
    if !escape_is(0xffu8, [0x5cu8, 0x78u8, 0x66u8, 0x66u8], 4usize) { return 28 }
    0
}

fn constant_operations(): i32 {
    if u8.BITS != 8u32 || u8.MIN != 0u8 || u8.MAX != 255u8 { return 30 }
    if i8.BITS != 8u32 || i8.MIN != -128i8 || i8.MAX != 127i8 { return 31 }
    if i16.BITS != 16u32 || i16.MIN != -32768i16 || i16.MAX != 32767i16 { return 32 }
    if u16.BITS != 16u32 || u16.MIN != 0u16 || u16.MAX != 65535u16 { return 33 }
    if i32.BITS != 32u32 || i32.MIN != -2147483648i32 || i32.MAX != 2147483647i32 { return 34 }
    if u32.BITS != 32u32 || u32.MIN != 0u32 || u32.MAX != 4294967295u32 { return 35 }
    if i64.BITS != 64u32 || i64.MIN != -9223372036854775808i64 || i64.MAX != 9223372036854775807i64 { return 36 }
    if u64.BITS != 64u32 || u64.MIN != 0u64 || u64.MAX != 18446744073709551615u64 { return 37 }
    if i128.BITS != 128u32 || i128.MIN != -170141183460469231731687303715884105728i128 { return 38 }
    if u128.BITS != 128u32 || u128.MIN != 0u128 || u128.MAX != 340282366920938463463374607431768211455u128 { return 39 }
    if isize.BITS != usize.BITS || isize.MIN != -isize.MAX - 1isize || usize.MIN != 0usize { return 40 }
    if f32.MIN != -f32.MAX || f64.MIN != -f64.MAX { return 42 }
    if char.MAX != '\u{10ffff}' || char.MIN != '\0' || char.REPLACEMENT_CHARACTER != '\u{fffd}' { return 43 }
    if char.MAX_LEN_UTF8 != 4usize || char.MAX_LEN_UTF16 != 2usize { return 44 }
    0
}

fn main(): i32 {
    let a = bool_operations()
    if a != 0 { return a }
    let b = decode_operations()
    if b != 0 { return b }
    let c = escape_operations()
    if c != 0 { return c }
    let d = constant_operations()
    if d != 0 { return d }
    0
}
