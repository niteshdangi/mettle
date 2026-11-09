// profiles: debug release
// Wrapping's value traits delegate to the wrapped integer: Clone/Copy,
// equality and ordering, Default (zero), Debug and Display (the integer's
// text) and Hash (equal values hash equally).
import core.num.Wrapping
import core.clone.Clone
import core.cmp
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.hash.hash_one
import alloc.string.ToString
import core.fmt
import core.fmt.Debug

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
    0
}
