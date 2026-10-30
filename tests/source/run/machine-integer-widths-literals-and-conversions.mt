
fn accept(value: i64): i64 { value }
fn main() {
    let byte: u8 = 0xff
    let small: i8 = -128
    let word: u16 = 0xffff
    let signed: i16 = -32768
    let count: u32 = 0xffffffff
    let long: u64 = 18446744073709551615
    let minimum: i64 = -9223372036854775808
    let wide: u128 = 340282366920938463463374607431768211455
    let wide_min: i128 = -170141183460469231731687303715884105728
    let native: usize = 0b10_1010
    let offset: isize = -42
    let inferred = 42
    let values: [u16;2] = [20,22]
    let narrowed = 0x1234u32 as u8
    if byte == 255u8 && small as i64 == -128i64 &&
       word == 65535u16 && signed as i32 == -32768 &&
       count as i32 == -1 && long as i64 == -1 &&
       minimum as u64 == 9223372036854775808u64 &&
       wide >> 120u8 == 255u128 &&
       wide_min >> 127u16 == -1i128 &&
       native as i64 == 42 && offset as i32 == -42 &&
       accept(inferred) == 42 && narrowed == 52u8 &&
       values[0] + values[1] == 42u16 { 0 } else { 1 }
}
