// Checked construction of Unicode scalar values.
import super.clone.Clone
import super.cmp.{Eq, PartialEq}
import super.convert.{From, TryFrom}
import super.error.{Error as CoreError}
import super.fmt.{Debug, Display, Error, Formatter, fmt_radix}
import super.iter.{Iterator, OwnedIterable}
import super.text.{FromStr, Text}

// The failure of a `char` conversion from an integer that is not a scalar value.
pub copy type CharTryFromError { }
extend CharTryFromError implements PartialEq {
    fn eq(other: read CharTryFromError): bool { true }
}
extend CharTryFromError implements Eq {}
extend CharTryFromError implements Clone {
    fn clone(): CharTryFromError { self }
}
extend CharTryFromError implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("CharTryFromError(())")
    }
}
extend CharTryFromError implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("converted integer out of range for `char`")
    }
}
extend CharTryFromError implements CoreError {}

// The failure of a conversion from a `char` whose code point does not fit the target.
pub copy type TryFromCharError { }
extend TryFromCharError implements PartialEq {
    fn eq(other: read TryFromCharError): bool { true }
}
extend TryFromCharError implements Eq {}
extend TryFromCharError implements Clone {
    fn clone(): TryFromCharError { self }
}
extend TryFromCharError implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("TryFromCharError(())")
    }
}
extend TryFromCharError implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("unicode code point out of range")
    }
}
extend TryFromCharError implements CoreError {}

pub copy enum CharErrorKind { EmptyString, TooManyChars }
pub copy type ParseCharError { pub kind: CharErrorKind }
extend ParseCharError implements PartialEq {
    fn eq(other: read ParseCharError): bool { (self.kind as u8) == (other.kind as u8) }
}
extend ParseCharError implements Eq {}
extend ParseCharError implements Clone {
    fn clone(): ParseCharError { self }
}
extend ParseCharError implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        match self.kind {
            CharErrorKind.EmptyString => try f.write_str("ParseCharError { kind: EmptyString }"),
            CharErrorKind.TooManyChars => try f.write_str("ParseCharError { kind: TooManyChars }")
        }
    }
}
extend ParseCharError implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        match self.kind {
            CharErrorKind.EmptyString => try f.write_str("cannot parse char from empty string"),
            CharErrorKind.TooManyChars => try f.write_str("too many characters in string")
        }
    }
}
extend ParseCharError implements CoreError {}

extend char implements FromStr {
    type Error = ParseCharError
    static fn from_str(input: read Text): char throws ParseCharError {
        var scalars = input.chars()
        let first = match scalars.next() {
            present(value) => value,
            none => { throw ParseCharError(CharErrorKind.EmptyString) }
        }
        if scalars.next().is_present() { throw ParseCharError(CharErrorKind.TooManyChars) }
        first
    }
}

extend char implements TryFrom<u32> {
    type Error = CharTryFromError
    static fn try_from(value: take u32): (char throws CharTryFromError) {
        match from_u32(value) {
            present(scalar) => success(scalar),
            none => failure(CharTryFromError())
        }
    }
}

extend char implements From<u8> {
    static fn from(value: take u8): char {
        unsafe { from_u32_unchecked(value as u32) }
    }
}

extend u32 implements From<char> {
    static fn from(value: take char): u32 { value as u32 }
}
extend u64 implements From<char> {
    static fn from(value: take char): u64 { value as u64 }
}
extend u128 implements From<char> {
    static fn from(value: take char): u128 { value as u128 }
}

macro char_try_from {
    ($($target:ident),*) => {
        $(
            extend $target implements TryFrom<char> {
                type Error = TryFromCharError
                static fn try_from(value: take char): ($target throws TryFromCharError) {
                    match (value as u32).checked_cast<$target>() {
                        present(converted) => success(converted),
                        none => failure(TryFromCharError())
                    }
                }
            }
        )*
    };
}

char_try_from!(u8, u16, usize)

pub fn from_u32(value: u32): char? {
    if value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
        return none
    }
    // Safety: the checks above establish a valid Unicode scalar value.
    present(unsafe { core.mem.transmute<char>(value) })
}

// Safety: `value` must be a Unicode scalar value (not a surrogate, at most U+10FFFF).
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
        else if scalar == 0x22u32 { '"' }
        else { return none }
    present(Escape(['\\', escaped, '\0', '\0', '\0', '\0', '\0', '\0', '\0', '\0'], 2usize, 0usize))
}

// Associated constants of the primitive char type (Unicode 16.0.0 tables).
extend char {
    pub const MAX: char = '\u{10ffff}'
    pub const MIN: char = '\0'
    pub const REPLACEMENT_CHARACTER: char = '\u{fffd}'
    pub const MAX_LEN_UTF8: usize = 4usize
    pub const MAX_LEN_UTF16: usize = 2usize
}

extend char {
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

    pub fn is_ascii_whitespace(): bool {
        // Tab, line feed, form feed, carriage return and space: not vertical tab.
        let value = self as u32
        value == 0x09u32 || value == 0x0au32 || value == 0x0cu32 || value == 0x0du32 ||
            value == 0x20u32
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

    // Writes the UTF-8 encoding into the front of `buffer` and returns that view.
    pub fn encode_utf8(buffer: mut [u8]): mut super.text.Text from buffer {
        let length = self.len_utf8()
        if buffer.len() < length {
            super.panic.panic("UTF-8 buffer is too small")
        }
        let value = self as u32
        if length == 1usize {
            buffer[0usize] = value as u8
        } else if length == 2usize {
            buffer[0usize] = (0xc0u32 | (value >> 6u32)) as u8
            buffer[1usize] = (0x80u32 | (value & 0x3fu32)) as u8
        } else if length == 3usize {
            buffer[0usize] = (0xe0u32 | (value >> 12u32)) as u8
            buffer[1usize] = (0x80u32 | ((value >> 6u32) & 0x3fu32)) as u8
            buffer[2usize] = (0x80u32 | (value & 0x3fu32)) as u8
        } else {
            buffer[0usize] = (0xf0u32 | (value >> 18u32)) as u8
            buffer[1usize] = (0x80u32 | ((value >> 12u32) & 0x3fu32)) as u8
            buffer[2usize] = (0x80u32 | ((value >> 6u32) & 0x3fu32)) as u8
            buffer[3usize] = (0x80u32 | (value & 0x3fu32)) as u8
        }
        let (encoded, _) = buffer.split_at_mut(length)
        // Safety: the bytes written above are the well-formed UTF-8 of one scalar.
        unsafe { super.text.from_utf8_unchecked_mut(encoded) }
    }

    pub fn encode_utf16(buffer: mut [u16]): mut [u16] from buffer {
        let length = self.len_utf16()
        if buffer.len() < length {
            super.panic.panic("UTF-16 buffer is too small")
        }
        let value = self as u32
        if length == 1usize {
            buffer[0usize] = value as u16
        } else {
            let scalar = value - 0x10000u32
            buffer[0usize] = (0xd800u32 + (scalar >> 10u32)) as u16
            buffer[1usize] = (0xdc00u32 + (scalar & 0x3ffu32)) as u16
        }
        let (encoded, _) = buffer.split_at_mut(length)
        encoded
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

// The failure of decoding an unpaired UTF-16 surrogate.
pub copy type DecodeUtf16Error { code: u16 }
extend DecodeUtf16Error implements PartialEq {
    fn eq(other: read DecodeUtf16Error): bool { self.code == other.code }
}
extend DecodeUtf16Error implements Eq {}
extend DecodeUtf16Error implements Clone {
    fn clone(): DecodeUtf16Error { self }
}
extend DecodeUtf16Error implements Debug {
    fn fmt(f: mut Formatter): Unit throws Error {
        var debug = try f.debug_struct("DecodeUtf16Error")
        try debug.field("code", read self.code)
        try debug.finish()
    }
}
extend DecodeUtf16Error implements Display {
    fn fmt(f: mut Formatter): Unit throws Error {
        try f.write_str("unpaired surrogate found: ")
        try fmt_radix(mut f, self.code as u64, false, 16u64, false, "")
    }
}
extend DecodeUtf16Error implements CoreError {}

extend DecodeUtf16Error {
    pub fn unpaired_surrogate(): u16 { self.code }
}

pub type DecodeUtf16<I> { iter: I; buffered: u16? }

pub fn decode_utf16<I: OwnedIterable<Item = u16>>(items: take I): DecodeUtf16<I.(OwnedIterable).IntoIter> {
    DecodeUtf16(I.(OwnedIterable).into_iter(items), none)
}

extend<I: Iterator<Item = u16>> DecodeUtf16<I> implements Iterator {
    type Item = (char throws DecodeUtf16Error)
    mut fn next(): (char throws DecodeUtf16Error)? {
        let pending = self.buffered
        self.buffered = none
        let unit = match pending {
            present(value) => value,
            none => match self.iter.next() {
                present(value) => value,
                none => { return none }
            }
        }
        if unit < 0xd800u16 || unit > 0xdfffu16 {
            return present(success(unsafe { from_u32_unchecked(unit as u32) }))
        }
        if unit >= 0xdc00u16 { return present(failure(DecodeUtf16Error(unit))) }
        let second = match self.iter.next() {
            present(value) => value,
            none => { return present(failure(DecodeUtf16Error(unit))) }
        }
        if second < 0xdc00u16 || second > 0xdfffu16 {
            self.buffered = present(second)
            return present(failure(DecodeUtf16Error(unit)))
        }
        let code = ((((unit - 0xd800u16) as u32) << 10u32) | ((second - 0xdc00u16) as u32)) + 0x10000u32
        present(success(unsafe { from_u32_unchecked(code) }))
    }
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
