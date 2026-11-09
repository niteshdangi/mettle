// profiles: debug release
// Conversions between bool, char, integer and float primitives, and the float
// arithmetic operator interfaces including read-operand forms. Expected values
// are computed independently.
import core.num
import core.char
import core.convert.{From, TryFrom}
import core.ops.{Add, Sub, Mul, Div, Rem, Neg}
import core.ops.{AddAssign, SubAssign, MulAssign, DivAssign, RemAssign}

fn add<A: Add<B>, B>(a: A, b: B): A.Output { a.add(b) }
fn sub<A: Sub<B>, B>(a: A, b: B): A.Output { a.sub(b) }
fn mul<A: Mul<B>, B>(a: A, b: B): A.Output { a.mul(b) }
fn div<A: Div<B>, B>(a: A, b: B): A.Output { a.div(b) }
fn rem<A: Rem<B>, B>(a: A, b: B): A.Output { a.rem(b) }
fn neg<A: Neg>(a: A): A.Output { a.neg() }
fn add_assign<A: AddAssign<B>, B>(a: take A, b: B): A { var x = a; x.add_assign(b); x }
fn sub_assign<A: SubAssign<B>, B>(a: take A, b: B): A { var x = a; x.sub_assign(b); x }
fn mul_assign<A: MulAssign<B>, B>(a: take A, b: B): A { var x = a; x.mul_assign(b); x }
fn div_assign<A: DivAssign<B>, B>(a: take A, b: B): A { var x = a; x.div_assign(b); x }
fn rem_assign<A: RemAssign<B>, B>(a: take A, b: B): A { var x = a; x.rem_assign(b); x }

fn yields<T: Copy + PartialEq, E>(result: (T throws E), expected: T): bool {
    match result { success(value) => value == expected, failure(_) => false }
}

fn is_err<T: Copy, E>(result: (T throws E)): bool {
    match result { success(_) => false, failure(_) => true }
}

fn float_operators(): i32 {
    if add(1.5f32, 2.25f32) != 3.75f32 || add(read 1.5f32, 2.25f32) != 3.75f32 { return 1 }
    if add(1.5f32, read 2.25f32) != 3.75f32 || add(read 1.5f32, read 2.25f32) != 3.75f32 { return 2 }
    if sub(3.0f32, 0.5f32) != 2.5f32 || sub(read 3.0f32, read 0.5f32) != 2.5f32 { return 3 }
    if mul(2.0f32, 3.0f32) != 6.0f32 || mul(read 2.0f32, 3.0f32) != 6.0f32 { return 4 }
    if mul(2.0f32, read 3.0f32) != 6.0f32 || mul(read 2.0f32, read 3.0f32) != 6.0f32 { return 5 }
    if div(7.0f32, 2.0f32) != 3.5f32 || div(read 7.0f32, read 2.0f32) != 3.5f32 { return 6 }
    if rem(7.5f32, 2.0f32) != 1.5f32 || rem(read 7.5f32, read 2.0f32) != 1.5f32 { return 7 }
    if neg(1.5f32) != (-1.5f32) || neg(read 1.5f32) != (-1.5f32) { return 8 }
    if add_assign(1.5f32, 2.25f32) != 3.75f32 || add_assign(1.5f32, read 2.25f32) != 3.75f32 { return 9 }
    if sub_assign(3.0f32, 0.5f32) != 2.5f32 || sub_assign(3.0f32, read 0.5f32) != 2.5f32 { return 10 }
    if mul_assign(2.0f32, 3.0f32) != 6.0f32 || mul_assign(2.0f32, read 3.0f32) != 6.0f32 { return 11 }
    if div_assign(7.0f32, 2.0f32) != 3.5f32 || div_assign(7.0f32, read 2.0f32) != 3.5f32 { return 12 }
    if rem_assign(7.5f32, 2.0f32) != 1.5f32 || rem_assign(7.5f32, read 2.0f32) != 1.5f32 { return 13 }

    if add(1.5f64, 2.25f64) != 3.75f64 || add(read 1.5f64, read 2.25f64) != 3.75f64 { return 20 }
    if sub(3.0f64, read 0.5f64) != 2.5f64 || sub(read 3.0f64, 0.5f64) != 2.5f64 { return 21 }
    if mul(2.0f64, read 3.0f64) != 6.0f64 || mul(read 2.0f64, read 3.0f64) != 6.0f64 { return 22 }
    if div(7.0f64, read 2.0f64) != 3.5f64 || div(read 7.0f64, 2.0f64) != 3.5f64 { return 23 }
    if rem(7.5f64, read 2.0f64) != 1.5f64 || rem(read 7.5f64, read 2.0f64) != 1.5f64 { return 24 }
    if neg(1.5f64) != (-1.5f64) || neg(read 1.5f64) != (-1.5f64) { return 25 }
    if add_assign(1.5f64, read 2.25f64) != 3.75f64 || mul_assign(2.0f64, read 3.0f64) != 6.0f64 { return 26 }
    if sub_assign(3.0f64, read 0.5f64) != 2.5f64 || div_assign(7.0f64, read 2.0f64) != 3.5f64 { return 27 }
    if rem_assign(7.5f64, read 2.0f64) != 1.5f64 { return 28 }
    0
}

fn integer_char_conversions(): i32 {
    if u32.(From<char>).from('a') != 97u32 || u32.(From<char>).from('\u{10ffff}') != 1114111u32 { return 30 }
    if u64.(From<char>).from('\u{20ac}') != 8364u64 { return 31 }
    if u128.(From<char>).from('\u{20ac}') != 8364u128 { return 32 }
    if !yields(u8.(TryFrom<char>).try_from('\u{ff}'), 255u8) || is_err(u8.(TryFrom<char>).try_from('\u{ff}')) { return 33 }
    if !is_err(u8.(TryFrom<char>).try_from('\u{100}')) { return 34 }
    if !yields(u16.(TryFrom<char>).try_from('\u{ffff}'), 65535u16) || !is_err(u16.(TryFrom<char>).try_from('\u{10000}')) { return 35 }
    if !yields(usize.(TryFrom<char>).try_from('a'), 97usize) { return 36 }
    0
}

fn bool_conversions(): i32 {
    if !yields(bool.(TryFrom<i8>).try_from(1i8), true) || !yields(bool.(TryFrom<i8>).try_from(0i8), false) { return 40 }
    if !is_err(bool.(TryFrom<i8>).try_from(2i8)) || !is_err(bool.(TryFrom<i8>).try_from((-1i8))) { return 41 }
    if !yields(bool.(TryFrom<i16>).try_from(1i16), true) || !is_err(bool.(TryFrom<i16>).try_from(2i16)) { return 42 }
    if !yields(bool.(TryFrom<i32>).try_from(0i32), false) || !is_err(bool.(TryFrom<i32>).try_from((-1i32))) { return 43 }
    if !yields(bool.(TryFrom<i64>).try_from(1i64), true) || !is_err(bool.(TryFrom<i64>).try_from(3i64)) { return 44 }
    if !yields(bool.(TryFrom<i128>).try_from(0i128), false) || !is_err(bool.(TryFrom<i128>).try_from(2i128)) { return 45 }
    if !yields(bool.(TryFrom<u8>).try_from(1u8), true) || !is_err(bool.(TryFrom<u8>).try_from(255u8)) { return 46 }
    if !yields(bool.(TryFrom<u16>).try_from(0u16), false) || !is_err(bool.(TryFrom<u16>).try_from(2u16)) { return 47 }
    if !yields(bool.(TryFrom<u32>).try_from(1u32), true) || !is_err(bool.(TryFrom<u32>).try_from(4u32)) { return 48 }
    if !yields(bool.(TryFrom<u64>).try_from(0u64), false) || !is_err(bool.(TryFrom<u64>).try_from(9u64)) { return 49 }
    if !yields(bool.(TryFrom<u128>).try_from(1u128), true) || !is_err(bool.(TryFrom<u128>).try_from(5u128)) { return 50 }
    0
}

fn char_conversions(): i32 {
    if char.(From<u8>).from(65u8) != 'A' || char.(From<u8>).from(255u8) != '\u{ff}' { return 60 }
    if !yields(char.(TryFrom<u32>).try_from(0x61u32), 'a') { return 61 }
    if !is_err(char.(TryFrom<u32>).try_from(0xd800u32)) || !is_err(char.(TryFrom<u32>).try_from(0x110000u32)) { return 62 }
    0
}

fn float_conversions(): i32 {
    if f32.(From<bool>).from(true) != 1.0f32 || f32.(From<i8>).from((-3i8)) != (-3.0f32) { return 70 }
    if f32.(From<i16>).from(300i16) != 300.0f32 || f32.(From<u8>).from(255u8) != 255.0f32 { return 71 }
    if f32.(From<u16>).from(65535u16) != 65535.0f32 { return 72 }
    if f64.(From<bool>).from(false) != 0.0f64 || f64.(From<i8>).from((-128i8)) != (-128.0f64) { return 73 }
    if f64.(From<i16>).from((-300i16)) != (-300.0f64) || f64.(From<i32>).from((-70000i32)) != (-70000.0f64) { return 74 }
    if f64.(From<u8>).from(200u8) != 200.0f64 || f64.(From<u16>).from(60000u16) != 60000.0f64 { return 75 }
    if f64.(From<u32>).from(4000000000u32) != 4000000000.0f64 || f64.(From<f32>).from(1.5f32) != 1.5f64 { return 76 }
    0
}

fn main(): i32 {
    let a = float_operators()
    if a != 0 { return a }
    let b = integer_char_conversions()
    if b != 0 { return b }
    let c = bool_conversions()
    if c != 0 { return c }
    let d = char_conversions()
    if d != 0 { return d }
    let e = float_conversions()
    if e != 0 { return e }
    0
}
