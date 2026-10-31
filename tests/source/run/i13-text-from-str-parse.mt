import core.from_str.{FromStr, CharErrorKind, FloatErrorKind}
import core.num.IntErrorKind

fn main(): i32 {
    match capture "42".parse_as<i32>() {
        success(value) => { if value != 42 { return 1 } },
        failure(_) => { return 1 }
    }
    match capture "300".parse_as<u8>() {
        success(_) => { return 2 },
        failure(error) => { if error.kind != IntErrorKind.PosOverflow { return 2 } }
    }
    match capture i64.(FromStr).from_str("-17") {
        success(value) => { if value != -17i64 { return 3 } },
        failure(_) => { return 3 }
    }
    match capture "true".parse_as<bool>() {
        success(value) => { if !value { return 4 } },
        failure(_) => { return 4 }
    }
    match capture "True".parse_as<bool>() {
        success(_) => { return 5 },
        failure(_) => {}
    }
    match capture "\u{e9}".parse_as<char>() {
        success(value) => { if value != '\u{e9}' { return 6 } },
        failure(_) => { return 6 }
    }
    match capture "ab".parse_as<char>() {
        success(_) => { return 7 },
        failure(error) => { if error.kind != CharErrorKind.TooManyChars { return 7 } }
    }
    match capture "".parse_as<char>() {
        success(_) => { return 8 },
        failure(error) => { if error.kind != CharErrorKind.EmptyText { return 8 } }
    }
    match capture "1.5".parse_as<f64>() {
        success(value) => { if value != 1.5f64 { return 9 } },
        failure(_) => { return 9 }
    }
    match capture "-2.5e3".parse_as<f64>() {
        success(value) => { if value != -2500.0f64 { return 10 } },
        failure(_) => { return 10 }
    }
    match capture "0.1".parse_as<f64>() {
        success(value) => { if value != 0.1f64 { return 11 } },
        failure(_) => { return 11 }
    }
    match capture ".5".parse_as<f32>() {
        success(value) => { if value != 0.5f32 { return 12 } },
        failure(_) => { return 12 }
    }
    match capture "+7.".parse_as<f64>() {
        success(value) => { if value != 7.0f64 { return 13 } },
        failure(_) => { return 13 }
    }
    match capture "-Infinity".parse_as<f64>() {
        success(value) => {
            if value != f64.from_bits(0xfff0000000000000u64) { return 14 }
        },
        failure(_) => { return 14 }
    }
    match capture "NaN".parse_as<f64>() {
        success(value) => { if value == value { return 15 } },
        failure(_) => { return 15 }
    }
    match capture "1e400".parse_as<f64>() {
        success(value) => { if value != f64.from_bits(0x7ff0000000000000u64) { return 16 } },
        failure(_) => { return 16 }
    }
    match capture "1e-400".parse_as<f64>() {
        success(value) => { if value != 0.0f64 { return 17 } },
        failure(_) => { return 17 }
    }
    match capture "".parse_as<f64>() {
        success(_) => { return 18 },
        failure(error) => { if error.kind != FloatErrorKind.Empty { return 18 } }
    }
    match capture "1.5x".parse_as<f64>() {
        success(_) => { return 19 },
        failure(error) => { if error.kind != FloatErrorKind.Invalid { return 19 } }
    }
    match capture "1e".parse_as<f64>() {
        success(_) => { return 20 },
        failure(_) => {}
    }
    match capture ".".parse_as<f64>() {
        success(_) => { return 21 },
        failure(_) => {}
    }
    0
}
