// profiles: debug release
// Evidence for the primitive char associated constants, the unchecked scalar
// constructor and UTF-8 encoding into a caller buffer (char::encode_utf8).

import core.char.{from_u32_unchecked}

fn checks_constants(): i32 {
    if char.MAX != '\u{10ffff}' { return 1 }
    if char.MIN != '\0' { return 2 }
    if char.REPLACEMENT_CHARACTER != '\u{fffd}' { return 3 }
    if char.MAX_LEN_UTF8 != 4usize || char.MAX_LEN_UTF16 != 2usize { return 4 }
    if char.UNICODE_VERSION != (17u8, 0u8, 0u8) { return 40 }
    if char.MAX.len_utf8() != char.MAX_LEN_UTF8 { return 6 }
    if char.MAX.len_utf16() != char.MAX_LEN_UTF16 { return 7 }
    0
}

fn checks_unchecked(): i32 {
    let ascii = unsafe { from_u32_unchecked(0x41u32) }
    if ascii != 'A' { return 10 }
    let astral = unsafe { from_u32_unchecked(0x10ffffu32) }
    if astral != char.MAX { return 11 }
    0
}

fn checks_encode_utf8(): i32 {
    var buffer = [0u8; 4]
    let one = '\u{41}'.encode_utf8(mut buffer)
    if one.len() != 1usize || one != "A" { return 20 }
    var two = [0u8; 4]
    let second = '\u{e9}'.encode_utf8(mut two)
    if second.len() != 2usize || second != "\u{e9}" { return 21 }
    if two[0usize] != 0xc3u8 || two[1usize] != 0xa9u8 { return 22 }
    var three = [0u8; 3]
    let third = '\u{4e2d}'.encode_utf8(mut three)
    if third.len() != 3usize || third != "\u{4e2d}" { return 23 }
    if three[0usize] != 0xe4u8 || three[1usize] != 0xb8u8 || three[2usize] != 0xadu8 { return 24 }
    var four = [0u8; 4]
    let fourth = '\u{1f600}'.encode_utf8(mut four)
    if fourth.len() != 4usize || fourth != "\u{1f600}" { return 25 }
    if four[0usize] != 0xf0u8 || four[1usize] != 0x9fu8 || four[2usize] != 0x98u8 || four[3usize] != 0x80u8 {
        return 26
    }
    var maximum = [0u8; 4]
    let last = char.MAX.encode_utf8(mut maximum)
    if last != "\u{10ffff}" { return 27 }
    0
}

fn main(): i32 {
    let first = checks_constants()
    if first != 0 { return first }
    let second = checks_unchecked()
    if second != 0 { return second }
    checks_encode_utf8()
}
