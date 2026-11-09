pub copy type Span { pub source: u32; pub begin: u32; pub end: u32 }
pub const SOURCE_BYTES: usize = 4294967295usize

pub fn invalid_utf8(read bytes: [u8]): usize? {
    var offset = 0usize
    while offset < bytes.len() {
        let first = bytes[offset]
        if first < 128u8 { offset += 1; continue }
        let width = if first >= 0xc2u8 && first <= 0xdfu8 { 2usize }
            else if first >= 0xe0u8 && first <= 0xefu8 { 3usize }
            else if first >= 0xf0u8 && first <= 0xf4u8 { 4usize }
            else { return present(offset) }
        if width > bytes.len() - offset { return present(offset) }
        var index = 1usize
        while index < width {
            if (bytes[offset + index] & 0xc0u8) != 0x80u8 { return present(offset) }
            index += 1
        }
        let second = bytes[offset + 1]
        if ((first == 0xe0u8 && second < 0xa0u8) || (first == 0xedu8 && second >= 0xa0u8)
            || (first == 0xf0u8 && second < 0x90u8) || (first == 0xf4u8 && second >= 0x90u8)) {
            return present(offset)
        }
        offset += width
    }
    none
}
