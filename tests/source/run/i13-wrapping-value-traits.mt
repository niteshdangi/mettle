// profiles: debug release
// Wrapping's value traits delegate to the wrapped integer: Clone/Copy,
// equality and ordering, Default (zero), Debug and Display (the integer's
// text) and Hash (equal values hash equally).
import core.num.{Saturating, Wrapping}
import core.clone.Clone
import core.cmp
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.hash.hash_one
import alloc.string.ToString
import core.fmt
import core.fmt.Debug
import core.ops.{Add, AddAssign, Div, Neg}
import core.iter.Iterator

fn debug_is<T: Debug>(read value: T, read expected: core.text.Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    let a = Wrapping(250u8)
    let b = a
    if a.clone() != a || b.value != 250u8 { return 1 }
    if Wrapping(-3i64) >= Wrapping(2i64) || Wrapping(2i64).cmp(read Wrapping(-3i64)) != Ordering.Greater { return 2 }
    if Wrapping(5u128).partial_cmp(read Wrapping(5u128)) != present(Ordering.Equal) { return 3 }
    let zero: Wrapping<i16> = Wrapping<i16>.default()
    if zero.value != 0i16 { return 4 }
    if Wrapping(-42i32).to_string().as_text() != "-42" { return 5 }
    if !debug_is(read Wrapping(7usize), "7") { return 6 }
    if hash_one(read Wrapping(9u32)) != hash_one(read Wrapping(9u32)) { return 7 }
    if hash_one(read Wrapping(9u32)) == hash_one(read Wrapping(10u32)) { return 8 }
    let high = Saturating(120i8)
    let increment = Saturating(20i8)
    let left = read high
    let right = read increment
    if (left + right).value != 127i8 { return 9 }
    var sum = Saturating(250u8)
    let addend = 10u8
    let borrowed_addend = read addend
    sum += borrowed_addend
    if sum.value != 255u8 ||
       (-Saturating(-128i8)).value != 127i8 ||
       Saturating(-128i8).abs().value != 127i8 ||
       Saturating(2i8).pow(7u32).value != 127i8 ||
       (Saturating(-128i8) / Saturating(-1i8)).value != 127i8 {
        return 10
    }
    let owned = Saturating(7i32.to_string())
    let cloned = owned.clone()
    if owned.value.as_text() != "7" || cloned.value.as_text() != "7" { return 11 }
    let wrapped = Wrapping(9i32.to_string())
    let wrapped_clone = wrapped.clone()
    if wrapped.value.as_text() != "9" || wrapped_clone.value.as_text() != "9" { return 12 }
    let terms = [Saturating(200u8), Saturating(100u8)]
    if terms.iter().sum<Saturating<u8>>().value != 255u8 ||
       terms.iter().copied().sum<Saturating<u8>>().value != 255u8 ||
       terms.iter().product<Saturating<u8>>().value != 255u8 ||
       terms.iter().copied().product<Saturating<u8>>().value != 255u8 {
        return 13
    }
    let empty: [Saturating<u8>; 0] = []
    if empty.iter().sum<Saturating<u8>>().value != 0u8 ||
       empty.iter().copied().sum<Saturating<u8>>().value != 0u8 ||
       empty.iter().product<Saturating<u8>>().value != 1u8 ||
       empty.iter().copied().product<Saturating<u8>>().value != 1u8 {
        return 14
    }
    0
}
