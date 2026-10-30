// Integer parsing from `Text` without allocation. Like Rust's `from_str_radix`:
// an optional leading `+` (and `-` for signed types), then at least one digit;
// no whitespace and no separators.

import super::cmp::{Eq, PartialEq};
import super::text::Text;

pub copy enum IntErrorKind { Empty, InvalidDigit, PosOverflow, NegOverflow, InvalidRadix }

impl IntErrorKind implements PartialEq {
    fn eq(other: read IntErrorKind): bool { (self as u8) == (other as u8) }
}
impl IntErrorKind implements Eq {}

pub copy type ParseIntError { pub kind: IntErrorKind }

fn digit_value(byte: u8): u32 {
    if byte >= 0x30u8 && byte <= 0x39u8 { return (byte - 0x30u8) as u32 }
    if byte >= 0x61u8 && byte <= 0x7au8 { return (byte - 0x61u8) as u32 + 10u32 }
    if byte >= 0x41u8 && byte <= 0x5au8 { return (byte - 0x41u8) as u32 + 10u32 }
    99u32
}

fn failure_of(kind: IntErrorKind): ParseIntError { ParseIntError(kind) }

// Parses the magnitude of `text` into at most `limit`; `negative` selects which
// overflow kind to report. `signed` allows a leading `-`.
fn parse_magnitude(text: read Text, radix: u32, signed: bool, limit_pos: u64, limit_neg: u64): u64 throws ParseIntError {
    if radix < 2u32 || radix > 36u32 { throw failure_of(IntErrorKind::InvalidRadix) }
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw failure_of(IntErrorKind::Empty) }
    var i = 0usize
    var negative = false
    if bytes[0] == 0x2bu8 {
        i = 1usize
    } else {
        if bytes[0] == 0x2du8 && signed { i = 1usize; negative = true }
    }
    if i == bytes.len() { throw failure_of(IntErrorKind::InvalidDigit) }
    let limit = if negative { limit_neg } else { limit_pos }
    var value = 0u64
    while i < bytes.len() {
        let digit = digit_value(bytes[i])
        if digit >= radix { throw failure_of(IntErrorKind::InvalidDigit) }
        match value.checked_mul(radix as u64) {
            present(scaled) => {
                match scaled.checked_add(digit as u64) {
                    present(next) => { value = next },
                    none => { throw failure_of(if negative { IntErrorKind::NegOverflow } else { IntErrorKind::PosOverflow }) }
                }
            },
            none => { throw failure_of(if negative { IntErrorKind::NegOverflow } else { IntErrorKind::PosOverflow }) }
        }
        if value > limit {
            // keep scanning so that a later invalid digit wins over overflow
            var j = i + 1usize
            while j < bytes.len() {
                if digit_value(bytes[j]) >= radix { throw failure_of(IntErrorKind::InvalidDigit) }
                j += 1usize
            }
            throw failure_of(if negative { IntErrorKind::NegOverflow } else { IntErrorKind::PosOverflow })
        }
        i += 1usize
    }
    // The sign travels in the top bit of the caller's wide cast: encode via negative flag.
    if negative { value.wrapping_neg() } else { value }
}

pub interface FromText: Sized {
    static fn from_text_radix(text: read Text, radix: u32): Self throws ParseIntError;
}

pub fn parse<T: FromText>(text: read Text): T throws ParseIntError {
    try <T implements FromText>::from_text_radix(text, 10u32)
}
pub fn parse_radix<T: FromText>(text: read Text, radix: u32): T throws ParseIntError {
    try <T implements FromText>::from_text_radix(text, radix)
}
impl i8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 127u64, 128u64)
        raw as i64 as i8
    }
}
impl i16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 32767u64, 32768u64)
        raw as i64 as i16
    }
}
impl i32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 2147483647u64, 2147483648u64)
        raw as i64 as i32
    }
}
impl i64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u64, 9223372036854775808u64)
        raw as i64 as i64
    }
}
impl isize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): isize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u64, 9223372036854775808u64)
        raw as i64 as isize
    }
}
impl u8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 255u64, 0u64)
        raw as u8
    }
}
impl u16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 65535u64, 0u64)
        raw as u16
    }
}
impl u32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 4294967295u64, 0u64)
        raw as u32
    }
}
impl u64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 18446744073709551615u64, 0u64)
        raw as u64
    }
}
impl usize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): usize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 18446744073709551615u64, 0u64)
        raw as usize
    }
}
