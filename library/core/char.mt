// Checked construction of Unicode scalar values.
import super.iter.Iterator

pub fn from_u32(value: u32): char? {
    if value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
        return none
    }
    // Safety: the checks above establish a valid Unicode scalar value.
    present(unsafe { core.mem.transmute<char>(value) })
}

extend char {
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
