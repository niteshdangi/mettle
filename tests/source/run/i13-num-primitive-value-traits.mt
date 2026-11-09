// profiles: debug release
// Value traits of every integer, bool, char and float primitive: Copy, Clone,
// Default, equality and ordering, hashing, Debug/Display and FromStr. Expected
// values are computed independently.
import core.num
import core.clone.Clone
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.default.Default
import core.fmt
import core.fmt.{Debug, Display}
import core.hash
import core.hash.{Hash, Hasher}
import core.text.{FromStr, Text}

fn debug_is<T: Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
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

fn display_is<T: Display>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    match capture fmt.write(mut writer, value) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let written = writer.len()
    match fmt.written_text(read buffer, written) {
        present(actual) => actual == expected,
        none => false
    }
}

fn parses_to<T: FromStr + PartialEq>(read text: Text, expected: T): bool {
    match capture T.(FromStr).from_str(text) {
        success(value) => value == expected,
        failure(_) => false
    }
}

fn rejects<T: FromStr>(read text: Text): bool {
    match capture T.(FromStr).from_str(text) {
        success(_) => false,
        failure(_) => true
    }
}

fn hashes_equal<T: Hash>(read left: T, read right: T): bool {
    hash.hash_one(left) == hash.hash_one(right)
}

fn reflexive<T: Eq>(read value: T): bool { value == value }

fn integer_traits<T: Copy + Clone + Default + Eq + Ord + Hash + Debug + Display + FromStr>(
    zero: T, low: T, high: T, read low_text: Text, read high_text: Text
): i32 {
    let copied = low
    if copied != low { return 1 }
    let cloned = low.clone()
    if cloned != low || T.(Default).default() != zero { return 2 }
    if low >= high || low.cmp(read high) != Ordering.Less { return 3 }
    if high.cmp(read high) != Ordering.Equal || !hashes_equal(read low, read low) { return 4 }
    if !hashes_equal(read high, read high) || hashes_equal(read low, read high) { return 5 }
    if !debug_is(read low, low_text) || !display_is(read high, high_text) { return 6 }
    if !parses_to(low_text, low) || !parses_to(high_text, high) { return 7 }
    if !rejects<T>("") || !rejects<T>("x") { return 8 }
    0
}

fn bool_traits(): i32 {
    let copied = true
    if copied != true || false.clone() != false { return 1 }
    if bool.default() != false { return 2 }
    if !(false < true) || true.cmp(read false) != Ordering.Greater { return 3 }
    if !hashes_equal(read true, read true) || hashes_equal(read true, read false) { return 4 }
    if !debug_is(read true, "true") || !display_is(read false, "false") { return 5 }
    if !parses_to<bool>("true", true) || !parses_to<bool>("false", false) { return 6 }
    if !rejects<bool>("True") || !rejects<bool>("") { return 7 }
    if !reflexive(read true) || !reflexive(read false) { return 8 }
    0
}

fn char_traits(): i32 {
    let copied = 'a'
    if copied != 'a' || 'a'.clone() != 'a' || char.default() != '\0' { return 1 }
    if !('a' < 'b') || 'b'.cmp(read 'a') != Ordering.Greater { return 2 }
    if !hashes_equal(read 'x', read 'x') || hashes_equal(read 'x', read 'y') { return 3 }
    if !debug_is(read 'a', "'a'") || !display_is(read 'b', "b") { return 4 }
    if !parses_to<char>("x", 'x') || !rejects<char>("") || !rejects<char>("ab") { return 5 }
    if !reflexive(read 'z') { return 6 }
    0
}

fn float_traits<T: Copy + Clone + Default + PartialEq + PartialOrd + Debug + Display + FromStr>(
    zero: T, value: T, read text: Text
): i32 {
    let copied = value
    if copied != value || value.clone() != value || T.(Default).default() != zero { return 1 }
    if zero == value || !(zero < value || value < zero) { return 2 }
    if !debug_is(read value, text) || !display_is(read value, text) { return 3 }
    if !parses_to(text, value) || !rejects<T>("") || !rejects<T>("abc") { return 4 }
    0
}

fn integers(): i32 {
    let a = integer_traits(0i8, (-5i8), 7i8, "-5", "7")
    if a != 0 { return 100 + a }
    let b = integer_traits(0i16, (-300i16), 700i16, "-300", "700")
    if b != 0 { return 110 + b }
    let c = integer_traits(0i32, (-70000i32), 70000i32, "-70000", "70000")
    if c != 0 { return 120 + c }
    let d = integer_traits(0i64, (-9i64), 1234567890123i64, "-9", "1234567890123")
    if d != 0 { return 130 + d }
    let e = integer_traits(0i128, (-9i128), 99i128, "-9", "99")
    if e != 0 { return 140 + e }
    let f = integer_traits(0isize, (-4isize), 44isize, "-4", "44")
    if f != 0 { return 150 + f }
    let g = integer_traits(0u8, 3u8, 200u8, "3", "200")
    if g != 0 { return 160 + g }
    let h = integer_traits(0u16, 3u16, 60000u16, "3", "60000")
    if h != 0 { return 170 + h }
    let i = integer_traits(0u32, 3u32, 4000000000u32, "3", "4000000000")
    if i != 0 { return 180 + i }
    let j = integer_traits(0u64, 3u64, 18000000000000000000u64, "3", "18000000000000000000")
    if j != 0 { return 190 + j }
    let k = integer_traits(0u128, 3u128, 99u128, "3", "99")
    if k != 0 { return 200 + k }
    let l = integer_traits(0usize, 3usize, 4000usize, "3", "4000")
    if l != 0 { return 210 + l }
    0
}

fn floats(): i32 {
    let a = float_traits(0.0f32, 1.5f32, "1.5")
    if a != 0 { return 300 + a }
    let b = float_traits(0.0f64, (-2.5f64), "-2.5")
    if b != 0 { return 310 + b }
    0
}

fn main(): i32 {
    let i = integers()
    if i != 0 { return i }
    let b = bool_traits()
    if b != 0 { return 400 + b }
    let c = char_traits()
    if c != 0 { return 410 + c }
    let f = floats()
    if f != 0 { return f }
    0
}
