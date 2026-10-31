// Checked construction of Unicode scalar values.
pub fn from_u32(value: u32): char? {
    if value > 0x10ffffu32 || (value >= 0xd800u32 && value <= 0xdfffu32) {
        return none
    }
    // Safety: the checks above establish a valid Unicode scalar value.
    present(unsafe { core.mem.transmute<char>(value) })
}

extend char {
    // Unicode 16.0.0 White_Space property, encoded as compact ranges.
    pub fn is_whitespace(): bool {
        let value = self as u32
        value >= 0x09u32 && value <= 0x0du32 ||
            value == 0x20u32 || value == 0x85u32 ||
            value == 0xa0u32 || value == 0x1680u32 ||
            value >= 0x2000u32 && value <= 0x200au32 ||
            value == 0x2028u32 || value == 0x2029u32 ||
            value == 0x202fu32 || value == 0x205fu32 ||
            value == 0x3000u32
    }
}
