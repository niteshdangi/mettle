import core.char.{decode_utf16, from_u32_unchecked}
import core.iter.Iterator

fn main(): i32 {
    if char.MIN != '\0' || char.MAX != '\u{10ffff}' ||
        char.REPLACEMENT_CHARACTER != '\u{fffd}' ||
        char.MAX_LEN_UTF8 != 4usize || char.MAX_LEN_UTF16 != 2usize {
        return 1
    }
    if char.UNICODE_VERSION.0 != 16u8 || char.UNICODE_VERSION.1 != 0u8 ||
        char.UNICODE_VERSION.2 != 0u8 {
        return 2
    }
    if unsafe { from_u32_unchecked(0x61u32) } != 'a' { return 3 }

    var ascii = [0x61u16]
    var decoded = decode_utf16(ascii.iter().copied())
    match take decoded.next() {
        present(item) => match take item {
            success(value) => { if value != 'a' { return 4 } },
            failure(_) => { return 4 }
        },
        none => { return 4 }
    }
    match take decoded.next() { present(_) => { return 5 }, none => {} }

    var pair = [0xd83eu16, 0xdd80u16]
    var emoji = decode_utf16(pair.iter().copied())
    match take emoji.next() {
        present(item) => match take item {
            success(value) => { if (value as u32) != 0x1f980u32 { return 6 } },
            failure(_) => { return 6 }
        },
        none => { return 6 }
    }

    var broken = [0xd800u16, 0x61u16]
    var recovered = decode_utf16(broken.iter().copied())
    match take recovered.next() {
        present(item) => match take item {
            success(_) => { return 7 },
            failure(error) => { if error.unpaired != 0xd800u16 { return 7 } }
        },
        none => { return 7 }
    }
    match take recovered.next() {
        present(item) => match take item {
            success(value) => { if value != 'a' { return 8 } },
            failure(_) => { return 8 }
        },
        none => { return 8 }
    }
    0
}
