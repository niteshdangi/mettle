fn main(): i32 {
    var bytes = [0xffu8, 0xffu8, 0xffu8, 0xffu8]
    let ascii = 'A'.encode_utf8(mut bytes)
    if ascii.len() != 1usize || ascii != "A" || bytes[1usize] != 0xffu8 {
        return 1
    }
    let two = '\u{7ff}'.encode_utf8(mut bytes)
    if two.len() != 2usize || two != "\u{7ff}" ||
        bytes[0usize] != 0xdfu8 || bytes[1usize] != 0xbfu8 {
        return 2
    }
    let three = '\u{800}'.encode_utf8(mut bytes)
    if three.len() != 3usize || three != "\u{800}" || bytes[0usize] != 0xe0u8 ||
        bytes[1usize] != 0xa0u8 || bytes[2usize] != 0x80u8 {
        return 3
    }
    let four = '🦀'.encode_utf8(mut bytes)
    if four.len() != 4usize || four != "🦀" || bytes[0usize] != 0xf0u8 ||
        bytes[1usize] != 0x9fu8 || bytes[2usize] != 0xa6u8 || bytes[3usize] != 0x80u8 {
        return 4
    }
    0
}
