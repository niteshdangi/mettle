import alloc.string.from_text
import core.float
import core.fmt
import core.fmt.{Debug, Display}
import core.text.Text
import core.text.FromStr

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

fn rejects(read text: core.text.Text): bool {
    match capture f64.(FromStr).from_str(text) {
        success(_) => false,
        failure(_) => true
    }
}

fn f32_bits_are(read text: Text, expected: u32): bool {
    match capture f32.(FromStr).from_str(text) {
        success(value) => value.to_bits() == expected,
        failure(_) => false
    }
}

fn f64_bits_are(read text: Text, expected: u64): bool {
    match capture f64.(FromStr).from_str(text) {
        success(value) => value.to_bits() == expected,
        failure(_) => false
    }
}

fn long_midpoint_rounds_up(): bool {
    var text = from_text("1.00000000000000011102230246251565404236316680908203125")
    var index = 0usize
    while index < 1100usize {
        text.push('0')
        index += 1usize
    }
    text.push('1')
    match capture f64.(FromStr).from_str(text.as_text()) {
        success(value) => value.to_bits() == 0x3ff0000000000001u64,
        failure(_) => false
    }
}

fn main(): i32 {
    match capture f64.(FromStr).from_str("+1.25e2") {
        success(value) => if value != 125.0f64 { return 1 },
        failure(_) => { return 2 }
    }
    match capture f64.(FromStr).from_str("-0") {
        success(value) => if value.to_bits() != 0x8000000000000000u64 { return 3 },
        failure(_) => { return 4 }
    }
    match capture f64.(FromStr).from_str("5e-324") {
        success(value) => if value.to_bits() != 1u64 { return 5 },
        failure(_) => { return 6 }
    }
    match capture f64.(FromStr).from_str("1.7976931348623157e308") {
        success(value) => if value != f64.MAX { return 7 },
        failure(_) => { return 8 }
    }
    match capture f64.(FromStr).from_str("1e9999") {
        success(value) => if !value.is_infinite() { return 9 },
        failure(_) => { return 10 }
    }
    match capture f64.(FromStr).from_str("1e-9999") {
        success(value) => if value.to_bits() != 0u64 { return 11 },
        failure(_) => { return 12 }
    }
    match capture f64.(FromStr).from_str("-INFINITY") {
        success(value) => if !value.is_sign_negative() || !value.is_infinite() { return 13 },
        failure(_) => { return 14 }
    }
    match capture f64.(FromStr).from_str("NaN") {
        success(value) => if !value.is_nan() { return 15 },
        failure(_) => { return 16 }
    }
    if !rejects("+") || !rejects("1e") ||
       !rejects("1..0") || !rejects("1.0x") || !rejects(" 1.0") ||
       !rejects("1_0") || !rejects("0x1p0") ||
       !long_midpoint_rounds_up() {
        return 17
    }
    match capture f64.(FromStr).from_str("") {
        success(value) => { return 18 },
        failure(error) => {
            if !debug_is(read error, "ParseFloatError { kind: Empty }") ||
               !display_is(read error, "cannot parse float from empty string") {
                return 19
            }
        }
    }
    match capture f32.(FromStr).from_str("not-a-float") {
        success(value) => { return 20 },
        failure(error) => {
            if !debug_is(read error, "ParseFloatError { kind: Invalid }") ||
               !display_is(read error, "invalid float literal") {
                return 21
            }
        }
    }

    match capture f32.(FromStr).from_str("1.401298464324817e-45") {
        success(value) => if value.to_bits() != 1u32 { return 22 },
        failure(_) => { return 23 }
    }
    match capture f32.(FromStr).from_str("-0") {
        success(value) => if value.to_bits() != 0x80000000u32 { return 24 },
        failure(_) => { return 25 }
    }
    if !f32_bits_are("3.4028235e38", 0x7f7fffffu32) ||
       !f32_bits_are("1e9999", 0x7f800000u32) ||
       !f32_bits_are("-1e-9999", 0x80000000u32) ||
       !f32_bits_are("1.000000059604644775390625", 0x3f800000u32) ||
       !f32_bits_are("1.000000059604644775390626", 0x3f800001u32) {
        return 26
    }
    if !f64_bits_are(".5", 0x3fe0000000000000u64) ||
       !f64_bits_are("5.", 0x4014000000000000u64) ||
       !f64_bits_are("1.00000000000000011102230246251565404236316680908203125",
                    0x3ff0000000000000u64) {
        return 27
    }
    0
}
