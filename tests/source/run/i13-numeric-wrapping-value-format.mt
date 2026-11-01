import core.clone.Clone
import core.cmp.{Ord, Ordering}
import core.fmt
import core.fmt.{Binary, Debug, Display, LowerHex, Octal, UpperHex}
import core.hash
import core.hash.Hash
import core.num.Wrapping
import core.text.Text

fn value_contract<T: Copy + Ord + Hash + Clone>(
    left: read T, equal: read T, later: read T
): bool {
    left == equal &&
    left.cmp(read later) == Ordering.Less &&
    left.clone() == equal &&
    hash.hash_one(left) == hash.hash_one(equal)
}

fn clone_contract<T: Copy + Clone + PartialEq>(value: read T): bool {
    value.clone() == value
}

fn rendered<T: Display>(value: read T, expected: read Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    match capture fmt.write(mut writer, value) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn debugged<T: Debug>(value: read T, expected: read Text): bool {
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

fn binary<T: Binary>(value: read T, expected: read Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Binary).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn octal<T: Octal>(value: read T, expected: read Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Octal).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn lower_hex<T: LowerHex>(value: read T, expected: read Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(LowerHex).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn upper_hex<T: UpperHex>(value: read T, expected: read Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(UpperHex).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn formatting_contract<T: Display + Debug + Binary + Octal + LowerHex + UpperHex>(
    value: read T
): bool {
    rendered(value, "15") &&
    debugged(value, "15") &&
    binary(value, "1111") &&
    octal(value, "17") &&
    lower_hex(value, "f") &&
    upper_hex(value, "F")
}

fn main(): i32 {
    if !clone_contract(1.5f32) ||
       !clone_contract(1.5f64) ||
       !clone_contract(Wrapping(1.5f32)) ||
       !clone_contract(Wrapping(1.5f64)) {
        return 13
    }
    if !value_contract(Wrapping(15i8), Wrapping(15i8), Wrapping(16i8)) ||
       !formatting_contract(Wrapping(15i8)) { return 1 }
    if !value_contract(Wrapping(15i16), Wrapping(15i16), Wrapping(16i16)) ||
       !formatting_contract(Wrapping(15i16)) { return 2 }
    if !value_contract(Wrapping(15i32), Wrapping(15i32), Wrapping(16i32)) ||
       !formatting_contract(Wrapping(15i32)) { return 3 }
    if !value_contract(Wrapping(15i64), Wrapping(15i64), Wrapping(16i64)) ||
       !formatting_contract(Wrapping(15i64)) { return 4 }
    if !value_contract(Wrapping(15i128), Wrapping(15i128), Wrapping(16i128)) ||
       !formatting_contract(Wrapping(15i128)) { return 5 }
    if !value_contract(Wrapping(15isize), Wrapping(15isize), Wrapping(16isize)) ||
       !formatting_contract(Wrapping(15isize)) { return 6 }
    if !value_contract(Wrapping(15u8), Wrapping(15u8), Wrapping(16u8)) ||
       !formatting_contract(Wrapping(15u8)) { return 7 }
    if !value_contract(Wrapping(15u16), Wrapping(15u16), Wrapping(16u16)) ||
       !formatting_contract(Wrapping(15u16)) { return 8 }
    if !value_contract(Wrapping(15u32), Wrapping(15u32), Wrapping(16u32)) ||
       !formatting_contract(Wrapping(15u32)) { return 9 }
    if !value_contract(Wrapping(15u64), Wrapping(15u64), Wrapping(16u64)) ||
       !formatting_contract(Wrapping(15u64)) { return 10 }
    if !value_contract(Wrapping(15u128), Wrapping(15u128), Wrapping(16u128)) ||
       !formatting_contract(Wrapping(15u128)) { return 11 }
    if !value_contract(Wrapping(15usize), Wrapping(15usize), Wrapping(16usize)) ||
       !formatting_contract(Wrapping(15usize)) { return 12 }
    0
}
