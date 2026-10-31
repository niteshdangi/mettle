// Integer parsing from `Text` without allocation. Like Rust's `from_str_radix`:
// an optional leading `+` (and `-` for signed types), then at least one digit;
// no whitespace and no separators.

import super.cmp.{Eq, PartialEq}
import super.text.Text

pub copy enum IntErrorKind { Empty, InvalidDigit, PosOverflow, NegOverflow, InvalidRadix }

extend IntErrorKind implements PartialEq {
    fn eq(other: read IntErrorKind): bool { (self as u8) == (other as u8) }
}
extend IntErrorKind implements Eq {}

pub copy type ParseIntError { pub kind: IntErrorKind }
pub copy type Wrapping<T: Copy> { pub value: T }

extend Wrapping<u8> {
    pub fn reverse_bits(): Wrapping<u8> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u16> {
    pub fn reverse_bits(): Wrapping<u16> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u32> {
    pub fn reverse_bits(): Wrapping<u32> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u64> {
    pub fn reverse_bits(): Wrapping<u64> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<u128> {
    pub fn reverse_bits(): Wrapping<u128> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<usize> {
    pub fn reverse_bits(): Wrapping<usize> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i8> {
    pub fn reverse_bits(): Wrapping<i8> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i16> {
    pub fn reverse_bits(): Wrapping<i16> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i32> {
    pub fn reverse_bits(): Wrapping<i32> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i64> {
    pub fn reverse_bits(): Wrapping<i64> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<i128> {
    pub fn reverse_bits(): Wrapping<i128> {
        Wrapping(self.value.reverse_bits())
    }
}
extend Wrapping<isize> {
    pub fn reverse_bits(): Wrapping<isize> {
        Wrapping(self.value.reverse_bits())
    }
}

fn digit_value(byte: u8): u32 {
    if byte >= 0x30u8 && byte <= 0x39u8 { return (byte - 0x30u8) as u32 }
    if byte >= 0x61u8 && byte <= 0x7au8 { return (byte - 0x61u8) as u32 + 10u32 }
    if byte >= 0x41u8 && byte <= 0x5au8 { return (byte - 0x41u8) as u32 + 10u32 }
    99u32
}

fn failure_of(kind: IntErrorKind): ParseIntError { ParseIntError(kind) }

// Parses the magnitude of `text` into at most `limit`; `negative` selects which
// overflow kind to report. `signed` allows a leading `-`.
fn parse_magnitude(text: read Text, radix: u32, signed: bool, limit_pos: u128, limit_neg: u128): u128 throws ParseIntError {
    if radix < 2u32 || radix > 36u32 { throw failure_of(IntErrorKind.InvalidRadix) }
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw failure_of(IntErrorKind.Empty) }
    var i = 0usize
    var negative = false
    if bytes[0] == 0x2bu8 {
        i = 1usize
    } else {
        if bytes[0] == 0x2du8 && signed { i = 1usize; negative = true }
    }
    if i == bytes.len() { throw failure_of(IntErrorKind.InvalidDigit) }
    let limit = if negative { limit_neg } else { limit_pos }
    var value = 0u128
    var overflowed = false
    while i < bytes.len() {
        let digit = digit_value(bytes[i])
        if digit >= radix { throw failure_of(IntErrorKind.InvalidDigit) }
        if !overflowed {
            match value.checked_mul(radix as u128) {
                present(scaled) => {
                    match scaled.checked_add(digit as u128) {
                        present(next) => { value = next },
                        none => { overflowed = true }
                    }
                },
                none => { overflowed = true }
            }
            if value > limit { overflowed = true }
        }
        i += 1usize
    }
    if overflowed {
        throw failure_of(if negative { IntErrorKind.NegOverflow } else { IntErrorKind.PosOverflow })
    }
    // The sign travels in the top bit of the caller's wide cast: encode via negative flag.
    if negative { value.wrapping_neg() } else { value }
}

pub interface FromText: Sized {
    static fn from_text_radix(text: read Text, radix: u32): Self throws ParseIntError;
}

pub fn parse<T: FromText>(text: read Text): T throws ParseIntError {
    try T.(FromText).from_text_radix(text, 10u32)
}
pub fn parse_radix<T: FromText>(text: read Text, radix: u32): T throws ParseIntError {
    try T.(FromText).from_text_radix(text, radix)
}

pub fn from_str_radix<T: FromText>(
    text: read Text, radix: u32
): T throws ParseIntError {
    try parse_radix<T>(text, radix)
}

extend i8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 127u128, 128u128)
        raw as i64 as i8
    }
}
extend i16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 32767u128, 32768u128)
        raw as i64 as i16
    }
}
extend i32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 2147483647u128, 2147483648u128)
        raw as i64 as i32
    }
}
extend i64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as i64
    }
}
extend isize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): isize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, true, 9223372036854775807u128, 9223372036854775808u128)
        raw as i64 as isize
    }
}
extend u8 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u8 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 255u128, 0u128)
        raw as u8
    }
}
extend u16 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u16 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 65535u128, 0u128)
        raw as u16
    }
}
extend u32 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u32 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 4294967295u128, 0u128)
        raw as u32
    }
}
extend u64 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u64 throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, 18446744073709551615u128, 0u128)
        raw as u64
    }
}
extend usize implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): usize throws ParseIntError {
        let raw = try parse_magnitude(text, radix, false, ((-1isize) as usize) as u128, 0u128)
        raw as usize
    }
}
extend i128 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): i128 throws ParseIntError {
        let raw = try parse_magnitude(
            text, radix, true,
            170141183460469231731687303715884105727u128,
            170141183460469231731687303715884105728u128)
        raw as i128
    }
}
extend u128 implements FromText {
    static fn from_text_radix(text: read Text, radix: u32): u128 throws ParseIntError {
        try parse_magnitude(
            text, radix, false,
            340282366920938463463374607431768211455u128, 0u128)
    }
}
