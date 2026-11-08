// profiles: debug release
// ASCII whitespace is tab, line feed, form feed, carriage return and space;
// vertical tab (0x0b) is excluded for bytes, chars and the ASCII text
// operations, while Unicode `char.is_whitespace` still includes it.
import core.char
import core.text

fn main(): i32 {
    if 11u8.is_ascii_whitespace() { return 1 }
    if !12u8.is_ascii_whitespace() || !9u8.is_ascii_whitespace() { return 2 }
    if '\u{b}'.is_ascii_whitespace() { return 3 }
    if !'\u{c}'.is_ascii_whitespace() || !' '.is_ascii_whitespace() { return 4 }
    if !'\u{b}'.is_whitespace() { return 5 }
    let text = "\u{b} a\tb \u{b}"
    if text.trim_ascii() != "\u{b} a\tb \u{b}" { return 6 }
    if " \u{c}a\r\n".trim_ascii() != "a" { return 7 }
    var parts = "a\u{b}b c".split_ascii_whitespace()
    match parts.next() { present(first) => if first != "a\u{b}b" { return 8 }, none => { return 9 } }
    match parts.next() { present(second) => if second != "c" { return 10 }, none => { return 11 } }
    if parts.next().is_present() { return 12 }
    var unicode = "a\u{b}b".split_whitespace()
    match unicode.next() { present(first) => if first != "a" { return 13 }, none => { return 14 } }
    // Bytes above 0x7f are not ASCII (previously always reported ASCII).
    if 128u8.is_ascii() || 255u8.is_ascii() || !127u8.is_ascii() { return 15 }
    0
}
