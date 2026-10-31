// Parsing values from text. `FromStr` is the general contract; integers keep
// their radix-aware `num.FromText` entry points and implement `FromStr` on top
// of them. `Text.parse` stays the integer-only `num.FromText` form, so the
// general entry point is `parse_as`.
import super.error.Error
import super.fmt
import super.num
import super.text.Text

pub interface FromStr: Sized {
    type Err;
    static fn from_str(text: read Text): (Self throws Self.Err);
}

pub fn parse<T: FromStr>(text: read Text): (T throws T.(FromStr).Err) {
    try T.(FromStr).from_str(text)
}
extend Text {
    pub fn parse_as<T: FromStr>(): (T throws T.(FromStr).Err) {
        try parse<T>(read self)
    }
}

@derive(Clone, PartialEq, Eq, Debug)
pub copy type ParseBoolError {}
extend ParseBoolError implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("provided text was neither `true` nor `false`")
    }
}
extend ParseBoolError implements Error {}

extend bool implements FromStr {
    type Err = ParseBoolError
    static fn from_str(text: read Text): bool throws ParseBoolError {
        if text == "true" { return true }
        if text == "false" { return false }
        throw ParseBoolError()
    }
}

@derive(Clone, PartialEq, Eq, Debug)
pub copy enum CharErrorKind { EmptyText, TooManyChars }
@derive(Clone, PartialEq, Eq, Debug)
pub copy type ParseCharError { pub kind: CharErrorKind }
extend ParseCharError implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        match self.kind {
            CharErrorKind.EmptyText => { try f.write_str("cannot parse a character from empty text") },
            CharErrorKind.TooManyChars => { try f.write_str("too many characters in text") }
        }
    }
}
extend ParseCharError implements Error {}

extend char implements FromStr {
    type Err = ParseCharError
    static fn from_str(text: read Text): char throws ParseCharError {
        var chars = text.chars()
        let first = match chars.next() {
            present(value) => value,
            none => { throw ParseCharError(CharErrorKind.EmptyText) }
        }
        match chars.next() {
            present(_) => { throw ParseCharError(CharErrorKind.TooManyChars) },
            none => {}
        }
        first
    }
}

@derive(Clone, PartialEq, Eq, Debug)
pub copy enum FloatErrorKind { Empty, Invalid }
@derive(Clone, PartialEq, Eq, Debug)
pub copy type ParseFloatError { pub kind: FloatErrorKind }
extend ParseFloatError implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        match self.kind {
            FloatErrorKind.Empty => { try f.write_str("cannot parse a float from empty text") },
            FloatErrorKind.Invalid => { try f.write_str("invalid float literal") }
        }
    }
}
extend ParseFloatError implements Error {}

fn float_error(kind: FloatErrorKind): ParseFloatError { ParseFloatError(kind) }

fn is_digit_byte(byte: u8): bool { byte >= 0x30u8 && byte <= 0x39u8 }

// 10^exponent for `0 <= exponent <= 22`; every intermediate product is exact.
fn pow10_exact(exponent: i64): f64 {
    var value = 1.0f64
    var count = 0i64
    while count < exponent {
        value = value * 10.0f64
        count += 1i64
    }
    value
}

// Decimal text to the nearest `f64`. The value is correctly rounded when the
// significand fits 53 bits and the decimal exponent is within +-22 (one exact
// IEEE operation); outside that range the scaling is repeated multiplication or
// division and can differ from the correctly rounded value by an ulp or two.
// Digits after the 18th significant one are truncated.
fn parse_f64(text: read Text): f64 throws ParseFloatError {
    let bytes = text.as_bytes()
    if bytes.len() == 0usize { throw float_error(FloatErrorKind.Empty) }
    var i = 0usize
    var negative = false
    if bytes[0usize] == 0x2bu8 {
        i = 1usize
    } else if bytes[0usize] == 0x2du8 {
        i = 1usize
        negative = true
    }
    if i == bytes.len() { throw float_error(FloatErrorKind.Invalid) }
    let minus_one = f64.from_bits(0xbff0000000000000u64)
    let rest = match text.get(i, bytes.len()) {
        present(part) => part,
        none => { throw float_error(FloatErrorKind.Invalid) }
    }
    if rest.eq_ignore_ascii_case("inf") || rest.eq_ignore_ascii_case("infinity") {
        let infinity = f64.from_bits(0x7ff0000000000000u64)
        return if negative { infinity * minus_one } else { infinity }
    }
    if rest.eq_ignore_ascii_case("nan") {
        return f64.from_bits(0x7ff8000000000000u64)
    }

    var mantissa = 0u64
    var exponent = 0i64
    var seen_digit = false
    while i < bytes.len() && is_digit_byte(bytes[i]) {
        seen_digit = true
        if mantissa < 100000000000000000u64 {
            mantissa = mantissa * 10u64 + ((bytes[i] - 0x30u8) as u64)
        } else {
            exponent += 1i64
        }
        i += 1usize
    }
    if i < bytes.len() && bytes[i] == 0x2eu8 {
        i += 1usize
        while i < bytes.len() && is_digit_byte(bytes[i]) {
            seen_digit = true
            if mantissa < 100000000000000000u64 {
                mantissa = mantissa * 10u64 + ((bytes[i] - 0x30u8) as u64)
                exponent -= 1i64
            }
            i += 1usize
        }
    }
    if !seen_digit { throw float_error(FloatErrorKind.Invalid) }
    if i < bytes.len() && (bytes[i] == 0x65u8 || bytes[i] == 0x45u8) {
        i += 1usize
        var exponent_negative = false
        if i < bytes.len() && (bytes[i] == 0x2bu8 || bytes[i] == 0x2du8) {
            exponent_negative = bytes[i] == 0x2du8
            i += 1usize
        }
        if i == bytes.len() || !is_digit_byte(bytes[i]) {
            throw float_error(FloatErrorKind.Invalid)
        }
        var written = 0i64
        while i < bytes.len() && is_digit_byte(bytes[i]) {
            // Saturate far beyond any finite or subnormal result.
            if written < 100000i64 { written = written * 10i64 + ((bytes[i] - 0x30u8) as i64) }
            i += 1usize
        }
        if exponent_negative { exponent -= written } else { exponent += written }
    }
    if i != bytes.len() { throw float_error(FloatErrorKind.Invalid) }

    var value = 0.0f64
    if mantissa == 0u64 {
        value = 0.0f64
    } else if exponent > 400i64 {
        value = f64.from_bits(0x7ff0000000000000u64)
    } else if exponent < -400i64 {
        value = 0.0f64
    } else {
        value = mantissa as f64
        if exponent > 0i64 {
            var left = exponent
            while left > 22i64 {
                value = value * pow10_exact(22i64)
                left -= 22i64
            }
            value = value * pow10_exact(left)
        } else if exponent < 0i64 {
            var left = 0i64 - exponent
            while left > 22i64 {
                value = value / pow10_exact(22i64)
                left -= 22i64
            }
            value = value / pow10_exact(left)
        }
    }
    if negative { value * minus_one } else { value }
}

extend f64 implements FromStr {
    type Err = ParseFloatError
    static fn from_str(text: read Text): f64 throws ParseFloatError {
        try parse_f64(text)
    }
}
// Parsed as `f64` and narrowed, so a halfway decimal can round twice.
extend f32 implements FromStr {
    type Err = ParseFloatError
    static fn from_str(text: read Text): f32 throws ParseFloatError {
        let wide = try parse_f64(text)
        wide as f32
    }
}

extend i8 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): i8 throws num.ParseIntError { try num.parse<i8>(text) }
}
extend i16 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): i16 throws num.ParseIntError { try num.parse<i16>(text) }
}
extend i32 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): i32 throws num.ParseIntError { try num.parse<i32>(text) }
}
extend i64 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): i64 throws num.ParseIntError { try num.parse<i64>(text) }
}
extend i128 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): i128 throws num.ParseIntError { try num.parse<i128>(text) }
}
extend isize implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): isize throws num.ParseIntError { try num.parse<isize>(text) }
}
extend u8 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): u8 throws num.ParseIntError { try num.parse<u8>(text) }
}
extend u16 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): u16 throws num.ParseIntError { try num.parse<u16>(text) }
}
extend u32 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): u32 throws num.ParseIntError { try num.parse<u32>(text) }
}
extend u64 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): u64 throws num.ParseIntError { try num.parse<u64>(text) }
}
extend u128 implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): u128 throws num.ParseIntError { try num.parse<u128>(text) }
}
extend usize implements FromStr {
    type Err = num.ParseIntError
    static fn from_str(text: read Text): usize throws num.ParseIntError { try num.parse<usize>(text) }
}
