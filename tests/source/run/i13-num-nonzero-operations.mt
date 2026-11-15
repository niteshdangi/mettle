// profiles: debug release
// NonZero integers: construction, bit and arithmetic methods, traits, parsing,
// widening conversions and the operator forms with NonZero operands. Expected
// values are computed independently.
import core.num
import core.num.{IntErrorKind, NonZero}
import core.cmp.{Ordering, PartialEq, PartialOrd}
import core.clone.Clone
import core.convert.{From, TryFrom}
import core.fmt
import core.fmt.{Debug, Display}
import core.hash
import core.ops.{BitOr, Div, Rem, DivAssign, RemAssign, Neg}
import core.text.{FromStr, Text}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 16]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn bit_or<A: BitOr<B>, B>(a: A, b: B): A.Output { a.bitor(b) }
fn divide<A: Div<B>, B>(a: A, b: B): A.Output { a.div(b) }
fn remainder<A: Rem<B>, B>(a: A, b: B): A.Output { a.rem(b) }
fn negate<A: Neg>(a: A): A.Output { a.neg() }
fn divide_assign<A: DivAssign<B>, B>(take a: A, b: B): A { var x = a; x.div_assign(b); x }
fn remainder_assign<A: RemAssign<B>, B>(take a: A, b: B): A { var x = a; x.rem_assign(b); x }

fn construction_and_bits(): i32 {
    if NonZero<u8>.new(0u8).is_present() || NonZero<u8>.new(5u8).or_panic().get() != 5u8 { return 1 }
    let unchecked = unsafe { NonZero<u8>.new_unchecked(7u8) }
    if unchecked.get() != 7u8 { return 2 }
    let one = NonZero<u8>.new(1u8).or_panic()
    if one.leading_zeros() != 7u32 || one.trailing_zeros() != 0u32 { return 3 }
    let eight = NonZero<u8>.new(8u8).or_panic()
    if eight.trailing_zeros() != 3u32 || eight.count_ones().get() != 1u32 { return 4 }
    if !eight.is_power_of_two() || NonZero<u8>.new(6u8).or_panic().is_power_of_two() { return 5 }
    if NonZero<u32>.new(11u32).or_panic().count_ones().get() != 3u32 { return 6 }
    if one.bit_width().get() != 1u32 ||
       NonZero<u8>.new(128u8).or_panic().bit_width().get() != 8u32 ||
       eight.lowest_one() != 3u32 || eight.highest_one() != 3u32 ||
       NonZero<u8>.new(12u8).or_panic().isolate_lowest_one().get() != 4u8 ||
       NonZero<u8>.new(12u8).or_panic().isolate_highest_one().get() != 8u8 {
        return 7
    }
    0
}

fn checked_and_saturating(): i32 {
    let big = NonZero<u8>.new(250u8).or_panic()
    if big.checked_add(10u8).is_present() || big.checked_add(5u8).or_panic().get() != 255u8 { return 10 }
    let three = NonZero<u8>.new(3u8).or_panic()
    if three.checked_pow(5u32).or_panic().get() != 243u8 || three.checked_pow(6u32).is_present() { return 11 }
    if three.checked_mul(NonZero<u8>.new(4u8).or_panic()).or_panic().get() != 12u8 { return 12 }
    if big.saturating_add(10u8).get() != 255u8 || NonZero<u8>.new(16u8).or_panic().saturating_mul(NonZero<u8>.new(16u8).or_panic()).get() != 255u8 { return 13 }
    if NonZero<u8>.new(2u8).or_panic().saturating_pow(9u32).get() != 255u8 { return 14 }
    if three.div_ceil(NonZero<u8>.new(2u8).or_panic()).get() != 2u8 ||
       three.midpoint(NonZero<u8>.new(8u8).or_panic()).get() != 5u8 ||
       NonZero<u8>.new(15u8).or_panic().isqrt().get() != 3u8 ||
       NonZero<u8>.new(129u8).or_panic().checked_next_power_of_two().is_present() {
        return 15
    }
    0
}

fn signed_methods(): i32 {
    let minus_five = NonZero<i8>.new((-5i8)).or_panic()
    if minus_five.abs().get() != 5i8 || minus_five.unsigned_abs().get() != 5u8 { return 20 }
    if minus_five.is_positive() || !minus_five.is_negative() { return 21 }
    if negate(NonZero<i8>.new(5i8).or_panic()).get() != (-5i8) { return 22 }
    let minimum = NonZero<i8>.new(-128i8).or_panic()
    if minimum.checked_abs().is_present() || minimum.checked_neg().is_present() ||
       minimum.saturating_abs().get() != 127i8 || minimum.wrapping_abs().get() != -128i8 ||
       minimum.unsigned_abs().get() != 128u8 ||
       minimum.overflowing_neg() != (minimum, true) ||
       minimum.cast_unsigned().cast_signed() != minimum {
        return 23
    }
    let minus_two = NonZero<i8>.new(-2i8).or_panic()
    if minimum.saturating_mul(minus_two).get() != 127i8 ||
       minimum.saturating_mul(NonZero<i8>.new(2i8).or_panic()).get() != -128i8 ||
       minus_two.saturating_pow(7u32).get() != -128i8 ||
       minus_two.saturating_pow(8u32).get() != 127i8 ||
       minus_two.saturating_pow(0u32).get() != 1i8 {
        return 24
    }
    0
}

fn traits(): i32 {
    let three = NonZero<i32>.new(3i32).or_panic()
    let four = NonZero<i32>.new(4i32).or_panic()
    let copied = three
    if copied != three || three.clone() != three || three == four { return 30 }
    if !(three < four) || three.cmp(read four) != Ordering.Less { return 31 }
    if hash.hash_one(read three) != hash.hash_one(read NonZero<i32>.new(3i32).or_panic()) { return 32 }
    if !debug_is(read three, "3") { return 33 }
    0
}

fn parsing_and_conversions(): i32 {
    match capture NonZero<u32>.(FromStr).from_str("42") {
        success(value) => { if value.get() != 42u32 { return 40 } },
        failure(_) => { return 41 }
    }
    match capture NonZero<u32>.(FromStr).from_str("0") {
        success(_) => { return 42 },
        failure(error) => { if *error.kind() != IntErrorKind.Zero { return 43 } }
    }
    match capture NonZero<u32>.(FromStr).from_str("x") {
        success(_) => { return 44 },
        failure(_) => {}
    }
    let back = u8.(From<NonZero<u8>>).from(NonZero<u8>.new(9u8).or_panic())
    if back != 9u8 { return 45 }
    if NonZero<u32>.(From<NonZero<u8>>).from(NonZero<u8>.new(200u8).or_panic()).get() != 200u32 { return 46 }
    if NonZero<i64>.(From<NonZero<i32>>).from(NonZero<i32>.new((-7i32)).or_panic()).get() != (-7i64) { return 47 }
    match NonZero<u16>.(TryFrom<NonZero<u8>>).try_from(NonZero<u8>.new(200u8).or_panic()) {
        success(value) => { if value.get() != 200u16 { return 48 } }
    }
    match NonZero<u8>.(TryFrom<NonZero<u16>>).try_from(NonZero<u16>.new(256u16).or_panic()) {
        success(_) => { return 49 },
        failure(_) => {}
    }
    0
}

fn operator_forms(): i32 {
    let five = NonZero<u8>.new(5u8).or_panic()
    if bit_or(five, 8u8).get() != 13u8 { return 50 }
    if bit_or(8u8, five).get() != 13u8 { return 51 }
    let eight = NonZero<u8>.new(8u8).or_panic()
    if divide(100u8, eight) != 12u8 || remainder(100u8, eight) != 4u8 { return 52 }
    if divide_assign(100u8, eight) != 12u8 || remainder_assign(100u8, eight) != 4u8 { return 53 }
    0
}

fn per_type_operators(): i32 {
    if bit_or(1i8, NonZero<i8>.new(2i8).or_panic()).get() != 3i8 { return 60 }
    if bit_or(1i16, NonZero<i16>.new(2i16).or_panic()).get() != 3i16 { return 61 }
    if bit_or(1i32, NonZero<i32>.new(2i32).or_panic()).get() != 3i32 { return 62 }
    if bit_or(1i64, NonZero<i64>.new(2i64).or_panic()).get() != 3i64 { return 63 }
    if bit_or(1i128, NonZero<i128>.new(2i128).or_panic()).get() != 3i128 { return 64 }
    if bit_or(1isize, NonZero<isize>.new(2isize).or_panic()).get() != 3isize { return 65 }
    if bit_or(1u8, NonZero<u8>.new(2u8).or_panic()).get() != 3u8 { return 66 }
    if bit_or(1u16, NonZero<u16>.new(2u16).or_panic()).get() != 3u16 { return 67 }
    if bit_or(1u32, NonZero<u32>.new(2u32).or_panic()).get() != 3u32 { return 68 }
    if bit_or(1u64, NonZero<u64>.new(2u64).or_panic()).get() != 3u64 { return 69 }
    if bit_or(1u128, NonZero<u128>.new(2u128).or_panic()).get() != 3u128 { return 70 }
    if bit_or(1usize, NonZero<usize>.new(2usize).or_panic()).get() != 3usize { return 71 }
    let n16 = NonZero<u16>.new(8u16).or_panic()
    let n32 = NonZero<u32>.new(8u32).or_panic()
    let n64 = NonZero<u64>.new(8u64).or_panic()
    let n128 = NonZero<u128>.new(8u128).or_panic()
    let nsize = NonZero<usize>.new(8usize).or_panic()
    if divide(100u16, n16) != 12u16 || remainder(100u16, n16) != 4u16 { return 72 }
    if divide(100u32, n32) != 12u32 || remainder(100u32, n32) != 4u32 { return 73 }
    if divide(100u64, n64) != 12u64 || remainder(100u64, n64) != 4u64 { return 74 }
    if divide(100u128, n128) != 12u128 || remainder(100u128, n128) != 4u128 { return 75 }
    if divide(100usize, nsize) != 12usize || remainder(100usize, nsize) != 4usize { return 76 }
    if divide_assign(100u16, n16) != 12u16 || remainder_assign(100u16, n16) != 4u16 { return 77 }
    if divide_assign(100u64, n64) != 12u64 || remainder_assign(100u64, n64) != 4u64 { return 78 }
    0
}

fn main(): i32 {
    let a = construction_and_bits()
    if a != 0 { return a }
    let b = checked_and_saturating()
    if b != 0 { return b }
    let c = signed_methods()
    if c != 0 { return c }
    let d = traits()
    if d != 0 { return d }
    let e = parsing_and_conversions()
    if e != 0 { return e }
    let f = operator_forms()
    if f != 0 { return f }
    let g = per_type_operators()
    if g != 0 { return g }
    0
}
