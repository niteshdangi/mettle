// Checked construction of Unicode scalar values.
import super.iter.Iterator
import super.convert.{From, TryFrom}
import super.error.Error
import super.fmt

pub fn from_u32(value: u32): char? {
    if value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
        return none
    }
    // Safety: the checks above establish a valid Unicode scalar value.
    present(unsafe { core.mem.transmute<char>(value) })
}

// Safety: `value` is a Unicode scalar value, not a surrogate and not above U+10FFFF.
pub unsafe fn from_u32_unchecked(value: u32): char {
    unsafe { core.mem.transmute<char>(value) }
}

pub fn from_digit(value: u32, radix: u32): char? {
    if radix < 2u32 || radix > 36u32 || value >= radix { return none }
    let scalar = if value < 10u32 {
        0x30u32 + value
    } else {
        0x61u32 + value - 10u32
    }
    from_u32(scalar)
}

pub type Escape { values: [char; 10]; length: usize; position: usize }
extend Escape implements Iterator {
    type Item = char
    mut fn next(): char? {
        if self.position >= self.length { return none }
        let value = self.values[self.position]
        self.position += 1usize
        present(value)
    }
}

fn hex_digit(value: u32): char {
    let scalar = if value < 10u32 { 0x30u32 + value } else { 0x61u32 + value - 10u32 }
    match from_u32(scalar) { present(c) => c, none => '0' }
}

fn unicode_escape(value: u32): Escape {
    var values = ['\0'; 10]
    var length = 0usize
    values[length] = '\\'
    length += 1usize
    values[length] = 'u'
    length += 1usize
    values[length] = '{'
    length += 1usize
    var digits = [0u32; 6]
    var digit_count = 0usize
    var remaining = value
    while remaining != 0u32 {
        digits[digit_count] = remaining % 16u32
        remaining /= 16u32
        digit_count += 1usize
    }
    if digit_count == 0usize {
        values[length] = '0'
        length += 1usize
    }
    while digit_count != 0usize {
        digit_count -= 1usize
        values[length] = hex_digit(digits[digit_count])
        length += 1usize
    }
    values[length] = '}'
    length += 1usize
    Escape(values, length, 0usize)
}

fn short_escape(value: char): Escape? {
    let scalar = value as u32
    let escaped = if scalar == 0x00u32 { '0' }
        else if scalar == 0x09u32 { 't' }
        else if scalar == 0x0au32 { 'n' }
        else if scalar == 0x0du32 { 'r' }
        else if scalar == 0x5cu32 { '\\' }
        else if scalar == 0x27u32 { '\'' }
        else { return none }
    present(Escape(['\\', escaped, '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'], 2usize, 0usize))
}

extend char {
    pub const MIN: char = '\0'
    pub const MAX: char = '\u{10ffff}'
    pub const REPLACEMENT_CHARACTER: char = '\u{fffd}'
    pub const MAX_LEN_UTF8: usize = 4usize
    pub const MAX_LEN_UTF16: usize = 2usize
    // Matches library/core/unicode_data.mt, Unicode 16.0.0.
    pub const UNICODE_VERSION: (u8, u8, u8) = (16u8, 0u8, 0u8)

    pub fn is_ascii(): bool { (self as u32) <= 0x7fu32 }

    pub fn is_ascii_alphabetic(): bool {
        let value = self as u32
        value >= 0x41u32 && value <= 0x5au32 ||
            value >= 0x61u32 && value <= 0x7au32
    }

    pub fn is_ascii_alphanumeric(): bool {
        self.is_ascii_alphabetic() || self.is_ascii_digit()
    }

    pub fn is_ascii_control(): bool {
        let value = self as u32
        value <= 0x1fu32 || value == 0x7fu32
    }

    pub fn is_ascii_digit(): bool {
        let value = self as u32
        value >= 0x30u32 && value <= 0x39u32
    }

    pub fn is_ascii_graphic(): bool {
        let value = self as u32
        value >= 0x21u32 && value <= 0x7eu32
    }

    pub fn is_ascii_hexdigit(): bool {
        let value = self as u32
        value >= 0x30u32 && value <= 0x39u32 ||
            value >= 0x41u32 && value <= 0x46u32 ||
            value >= 0x61u32 && value <= 0x66u32
    }

    pub fn is_ascii_lowercase(): bool {
        let value = self as u32
        value >= 0x61u32 && value <= 0x7au32
    }

    pub fn is_ascii_punctuation(): bool {
        self.is_ascii_graphic() && !self.is_ascii_alphanumeric()
    }

    pub fn is_ascii_uppercase(): bool {
        let value = self as u32
        value >= 0x41u32 && value <= 0x5au32
    }

    // Horizontal tab, line feed, form feed, carriage return, and space.
    pub fn is_ascii_whitespace(): bool {
        let value = self as u32
        value == 0x09u32 || value == 0x0au32 || value == 0x0cu32 ||
            value == 0x0du32 || value == 0x20u32
    }

    pub fn is_control(): bool {
        let value = self as u32
        value <= 0x1fu32 || value >= 0x7fu32 && value <= 0x9fu32
    }

    pub fn is_digit(radix: u32): bool {
        match self.to_digit(radix) { present(_) => true, none => false }
    }

    pub fn to_digit(radix: u32): u32? {
        if radix < 2u32 || radix > 36u32 { return none }
        let value = self as u32
        let digit = if value >= 0x30u32 && value <= 0x39u32 {
            value - 0x30u32
        } else if value >= 0x61u32 && value <= 0x7au32 {
            value - 0x61u32 + 10u32
        } else if value >= 0x41u32 && value <= 0x5au32 {
            value - 0x41u32 + 10u32
        } else {
            return none
        }
        if digit < radix { present(digit) } else { none }
    }

    pub fn len_utf8(): usize {
        let value = self as u32
        if value < 0x80u32 { 1usize }
        else if value < 0x800u32 { 2usize }
        else if value < 0x10000u32 { 3usize }
        else { 4usize }
    }

    pub fn len_utf16(): usize {
        if (self as u32) < 0x10000u32 { 1usize } else { 2usize }
    }

    // Writes the scalar's UTF-16 code units into `dst` and returns that prefix.
    // Panics when `dst` is shorter than `len_utf16`.
    pub fn encode_utf16(dst: mut [u16]): mut [u16] from dst {
        let count = self.len_utf16()
        if dst.len() < count {
            super.panic.panic("encode_utf16 destination is shorter than the encoded scalar")
        }
        let value = self as u32
        if value < 0x10000u32 {
            dst[0] = value as u16
        } else {
            let scalar = value - 0x10000u32
            dst[0] = (0xd800u32 + (scalar >> 10u32)) as u16
            dst[1] = (0xdc00u32 + (scalar & 0x3ffu32)) as u16
        }
        dst.split_at_mut(count).0
    }

    // Writes the scalar's UTF-8 bytes into `dst` and returns the written prefix.
    // Check capacity first so a short buffer is left untouched on panic.
    pub fn encode_utf8(dst: mut [u8]): mut Text from dst {
        let value = self as u32
        let count = if value < 0x80u32 { 1usize }
            else if value < 0x800u32 { 2usize }
            else if value < 0x10000u32 { 3usize }
            else { 4usize }
        if dst.len() < count {
            super.panic.panic("encode_utf8 destination is shorter than the encoded scalar")
        }
        if count == 1usize {
            dst[0] = value as u8
        } else if count == 2usize {
            dst[0] = (0xc0u32 | (value >> 6u32)) as u8
            dst[1] = (0x80u32 | (value & 0x3fu32)) as u8
        } else if count == 3usize {
            dst[0] = (0xe0u32 | (value >> 12u32)) as u8
            dst[1] = (0x80u32 | ((value >> 6u32) & 0x3fu32)) as u8
            dst[2] = (0x80u32 | (value & 0x3fu32)) as u8
        } else {
            dst[0] = (0xf0u32 | (value >> 18u32)) as u8
            dst[1] = (0x80u32 | ((value >> 12u32) & 0x3fu32)) as u8
            dst[2] = (0x80u32 | ((value >> 6u32) & 0x3fu32)) as u8
            dst[3] = (0x80u32 | (value & 0x3fu32)) as u8
        }
        // Safety: these branches encode one validated scalar in canonical UTF-8.
        unsafe { super.text.from_utf8_unchecked_mut(dst.split_at_mut(count).0) }
    }

    pub fn to_ascii_lowercase(): char {
        let value = self as u32
        if value >= 0x41u32 && value <= 0x5au32 {
            match from_u32(value + 0x20u32) { present(c) => c, none => self }
        } else {
            self
        }
    }

    pub fn to_ascii_uppercase(): char {
        let value = self as u32
        if value >= 0x61u32 && value <= 0x7au32 {
            match from_u32(value - 0x20u32) { present(c) => c, none => self }
        } else {
            self
        }
    }

    pub mut fn make_ascii_lowercase(): Unit {
        let value = self.to_ascii_lowercase()
        unsafe { core.ptr.write(core.ptr.from_mut(self), value) }
    }

    pub mut fn make_ascii_uppercase(): Unit {
        let value = self.to_ascii_uppercase()
        unsafe { core.ptr.write(core.ptr.from_mut(self), value) }
    }

    pub fn eq_ignore_ascii_case(other: char): bool {
        self.to_ascii_lowercase() == other.to_ascii_lowercase()
    }

    pub fn escape_unicode(): Escape { unicode_escape(self as u32) }

    // Printable ASCII stays literal; everything else uses `\u{...}`.
    pub fn escape_default(): Escape {
        match take short_escape(self) {
            present(escaped) => escaped,
            none => {
                let value = self as u32
                if value >= 0x20u32 && value < 0x7fu32 {
                    Escape([self, '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'], 1usize, 0usize)
                } else {
                    unicode_escape(value)
                }
            }
        }
    }

    // Only control characters are escaped; other scalars stay literal.
    pub fn escape_debug(): Escape {
        match take short_escape(self) {
            present(escaped) => escaped,
            none => {
                if self.is_control() {
                    unicode_escape(self as u32)
                } else {
                    Escape([self, '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'], 1usize, 0usize)
                }
            }
        }
    }

    pub fn is_whitespace(): bool {
        let value = self as u32
        if value <= 0x7fu32 {
            return value >= 0x09u32 && value <= 0x0du32 || value == 0x20u32
        }
        super.unicode_data.is_white_space(value)
    }

    pub fn is_alphabetic(): bool {
        let value = self as u32
        if value <= 0x7fu32 {
            return value >= 0x41u32 && value <= 0x5au32 ||
                value >= 0x61u32 && value <= 0x7au32
        }
        super.unicode_data.is_alphabetic(value)
    }

    pub fn is_lowercase(): bool {
        let value = self as u32
        if value >= 0x61u32 && value <= 0x7au32 { return true }
        if value <= 0x7fu32 { return false }
        super.unicode_data.is_lowercase(value)
    }

    pub fn is_uppercase(): bool {
        let value = self as u32
        if value >= 0x41u32 && value <= 0x5au32 { return true }
        if value <= 0x7fu32 { return false }
        super.unicode_data.is_uppercase(value)
    }

    pub fn is_numeric(): bool {
        let value = self as u32
        if value >= 0x30u32 && value <= 0x39u32 { return true }
        if value <= 0x7fu32 { return false }
        super.unicode_data.is_numeric(value)
    }

    pub fn is_alphanumeric(): bool {
        let value = self as u32
        if value <= 0x7fu32 {
            return value >= 0x30u32 && value <= 0x39u32 ||
                value >= 0x41u32 && value <= 0x5au32 ||
                value >= 0x61u32 && value <= 0x7au32
        }
        self.is_alphabetic() || self.is_numeric()
    }

    pub fn is_cased(): bool {
        let value = self as u32
        if value >= 0x41u32 && value <= 0x5au32 ||
            value >= 0x61u32 && value <= 0x7au32 { return true }
        if value <= 0x7fu32 { return false }
        super.unicode_data.is_cased(value)
    }

    pub fn is_case_ignorable(): bool {
        super.unicode_data.is_case_ignorable(self as u32)
    }

    pub fn to_lowercase(): CaseMapping {
        let value = self as u32
        if value >= 0x41u32 && value <= 0x5au32 {
            let mapped = match from_u32(value + 0x20u32) {
                present(c) => c,
                none => self
            }
            return CaseMapping([mapped, self, self], 1usize, 0usize)
        }
        case_mapping(self, super.unicode_data.lowercase(value))
    }

    pub fn to_uppercase(): CaseMapping {
        let value = self as u32
        if value >= 0x61u32 && value <= 0x7au32 {
            let mapped = match from_u32(value - 0x20u32) {
                present(c) => c,
                none => self
            }
            return CaseMapping([mapped, self, self], 1usize, 0usize)
        }
        case_mapping(self, super.unicode_data.uppercase(value))
    }
}

fn case_mapping(source: char, mapping: [u32; 4]): CaseMapping {
    let first = match from_u32(mapping[1usize]) {
        present(c) => c,
        none => source
    }
    let second = if mapping[0usize] > 1u32 {
        match from_u32(mapping[2usize]) { present(c) => c, none => source }
    } else { source }
    let third = if mapping[0usize] > 2u32 {
        match from_u32(mapping[3usize]) { present(c) => c, none => source }
    } else { source }
    CaseMapping([first, second, third], mapping[0usize] as usize, 0usize)
}

pub type CaseMapping { values: [char; 3]; length: usize; position: usize }
extend CaseMapping implements Iterator {
    type Item = char
    mut fn next(): char? {
        if self.position >= self.length { return none }
        let value = self.values[self.position]
        self.position += 1usize
        present(value)
    }
}

// One unpaired UTF-16 code unit. A following unit, if any, stays buffered.
pub copy type DecodeUtf16Error { pub unpaired: u16 }

pub type DecodeUtf16<I> { iter: I; buf: u16? }

pub fn decode_utf16<I: Iterator<Item = u16>>(iter: take I): DecodeUtf16<I> {
    DecodeUtf16(iter, none)
}

extend<I: Iterator<Item = u16>> DecodeUtf16<I> implements Iterator {
    type Item = (char throws DecodeUtf16Error)
    mut fn next(): ((char throws DecodeUtf16Error))? {
        let unit = match take self.buf {
            present(buffered) => buffered,
            none => match take self.iter.next() {
                present(value) => value,
                none => { return none }
            }
        }
        if unit >= 0xd800u16 && unit <= 0xdbffu16 {
            match take self.iter.next() {
                present(next) => {
                    if next >= 0xdc00u16 && next <= 0xdfffu16 {
                        let scalar = 0x10000u32 +
                            ((unit as u32 - 0xd800u32) << 10u32) +
                            (next as u32 - 0xdc00u32)
                        match from_u32(scalar) {
                            present(value) => present(success(value)),
                            none => present(failure(DecodeUtf16Error(unit)))
                        }
                    } else {
                        self.buf = present(next)
                        present(failure(DecodeUtf16Error(unit)))
                    }
                },
                none => present(failure(DecodeUtf16Error(unit)))
            }
        } else if unit >= 0xdc00u16 && unit <= 0xdfffu16 {
            present(failure(DecodeUtf16Error(unit)))
        } else {
            match from_u32(unit as u32) {
                present(value) => present(success(value)),
                none => present(failure(DecodeUtf16Error(unit)))
            }
        }
    }
}

// Scalar and integer conversions. Widening is infallible; narrowing and
// integer-to-scalar conversions fail with a unit error naming the direction.
@derive(Clone, PartialEq, Eq, Debug)
pub copy type CharTryFromError {}
extend CharTryFromError implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("converted integer is not a Unicode scalar value")
    }
}
extend CharTryFromError implements Error {}

@derive(Clone, PartialEq, Eq, Debug)
pub copy type TryFromCharError {}
extend TryFromCharError implements fmt.Display {
    fn fmt(f: mut fmt.Formatter): Unit throws fmt.Error {
        try f.write_str("character does not fit in a byte")
    }
}
extend TryFromCharError implements Error {}

extend char implements From<u8> {
    static fn `from`(value: take u8): char { unsafe { from_u32_unchecked(value as u32) } }
}
extend u32 implements From<char> {
    static fn `from`(value: take char): u32 { value as u32 }
}
extend u64 implements From<char> {
    static fn `from`(value: take char): u64 { (value as u32) as u64 }
}
extend char implements TryFrom<u32> {
    type Error = CharTryFromError
    static fn try_from(value: take u32): char throws CharTryFromError {
        match from_u32(value) {
            present(scalar) => scalar,
            none => { throw CharTryFromError() }
        }
    }
}
extend u8 implements TryFrom<char> {
    type Error = TryFromCharError
    static fn try_from(value: take char): u8 throws TryFromCharError {
        let scalar = value as u32
        if scalar > 0xffu32 { throw TryFromCharError() }
        scalar as u8
    }
}
