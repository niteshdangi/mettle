// Checked construction of Unicode scalar values.
import super.iter.Iterator

pub fn from_u32(value: u32): char? {
    if value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
        return none
    }
    // Safety: the checks above establish a valid Unicode scalar value.
    present(unsafe { core.mem.transmute<char>(value) })
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
        let value = self as u32
        value >= 0x09u32 && value <= 0x0du32 || value == 0x20u32
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
