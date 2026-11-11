// profiles: debug release
// Evidence for V1 char operations on existing core.char methods: checked
// construction, digits, ASCII and Unicode predicates, case mapping, UTF-8 and
// UTF-16 lengths and encoding, and escapes. Each failed check returns a
// distinct nonzero code.

import core.option
import core.char.{from_u32, from_digit, Escape}
import alloc.string
import std.panic.CatchResult

fn panics(take action: fn(): Unit): bool {
    match take std.panic.catch_panic(action) {
        CatchResult.Panicked(_) => true,
        CatchResult.Returned(_) => false
    }
}

fn digit_is(value: u32?, expected: u32): bool {
    match value {
        present(found) => found == expected,
        none => false
    }
}

fn char_is(value: char?, expected: char): bool {
    match value {
        present(found) => found == expected,
        none => false
    }
}

fn escape_text(take text: Escape): string.String {
    var out = string.new()
    var pending = text
    while true {
        match pending.next() {
            present(c) => { out.push(c) },
            none => { break }
        }
    }
    out
}

fn checks_construction(): i32 {
    if !char_is(from_u32(0x10ffffu32), '\u{10ffff}') { return 1 }
    if from_u32(0x110000u32).is_present() { return 2 }
    if !char_is(from_u32(0xd7ffu32), '\u{d7ff}') { return 3 }
    if from_u32(0xd800u32).is_present() { return 4 }
    if from_u32(0xdfffu32).is_present() { return 5 }
    if from_u32(0xe000u32).is_none() { return 6 }
    if !char_is(from_u32(0x1f600u32), '\u{1f600}') { return 7 }
    if !char_is(from_digit(7u32, 10u32), '7') { return 8 }
    if !char_is(from_digit(10u32, 16u32), 'a') { return 9 }
    if !char_is(from_digit(35u32, 36u32), 'z') { return 10 }
    if from_digit(10u32, 10u32).is_present() { return 11 }
    if !char_is(from_digit(0u32, 1u32), '0') { return 12 }
    if !panics(fn(): Unit { let _ = from_digit(0u32, 37u32) }) { return 13 }
    if from_digit(0u32, 0u32).is_present() { return 14 }
    if from_digit(1u32, 1u32).is_present() { return 15 }
    0
}

fn checks_digits(): i32 {
    if !digit_is('f'.to_digit(16u32), 15u32) { return 20 }
    if !digit_is('Z'.to_digit(36u32), 35u32) { return 21 }
    if 'g'.to_digit(16u32).is_present() { return 22 }
    if '9'.to_digit(8u32).is_present() { return 23 }
    if !panics(fn(): Unit { let _ = 'z'.to_digit(37u32) }) { return 24 }
    if !'7'.is_digit(10u32) || '7'.is_digit(6u32) { return 25 }
    if '\u{0663}'.is_digit(10u32) { return 26 }
    if !panics(fn(): Unit { let _ = '0'.to_digit(0u32) }) { return 110 }
    if !panics(fn(): Unit { let _ = '0'.to_digit(1u32) }) { return 111 }
    if !panics(fn(): Unit { let _ = '?'.is_digit(0u32) }) { return 112 }
    if !panics(fn(): Unit { let _ = '?'.is_digit(1u32) }) { return 113 }
    if !panics(fn(): Unit { let _ = '?'.is_digit(37u32) }) { return 114 }
    0
}

fn checks_ascii_predicates(): i32 {
    if !'a'.is_ascii() || '\u{80}'.is_ascii() { return 30 }
    if !'Q'.is_ascii_alphabetic() || '1'.is_ascii_alphabetic() { return 31 }
    if !'1'.is_ascii_alphanumeric() || '-'.is_ascii_alphanumeric() { return 32 }
    if !'\u{1f}'.is_ascii_control() || !'\u{7f}'.is_ascii_control() || ' '.is_ascii_control() { return 33 }
    if !'0'.is_ascii_digit() || 'a'.is_ascii_digit() { return 34 }
    if !'!'.is_ascii_graphic() || ' '.is_ascii_graphic() || '\u{7f}'.is_ascii_graphic() { return 35 }
    if !'\t'.is_ascii_whitespace() || !'\u{0c}'.is_ascii_whitespace() ||
        '\u{0b}'.is_ascii_whitespace() || !' '.is_ascii_whitespace() { return 36 }
    if !'\r'.is_ascii_whitespace() || !'\n'.is_ascii_whitespace() { return 37 }
    if !'F'.is_ascii_hexdigit() || !'9'.is_ascii_hexdigit() || 'g'.is_ascii_hexdigit() { return 38 }
    if !'a'.is_ascii_lowercase() || 'A'.is_ascii_lowercase() { return 39 }
    if !'A'.is_ascii_uppercase() || 'a'.is_ascii_uppercase() { return 40 }
    if !'%'.is_ascii_punctuation() || 'a'.is_ascii_punctuation() || ' '.is_ascii_punctuation() { return 41 }
    0
}

fn checks_unicode_predicates(): i32 {
    if !'\t'.is_whitespace() || !'\u{0b}'.is_whitespace() || !' '.is_whitespace() { return 50 }
    if !'\u{85}'.is_whitespace() || !'\u{a0}'.is_whitespace() || !'\u{3000}'.is_whitespace() { return 51 }
    if '\u{200b}'.is_whitespace() || 'x'.is_whitespace() { return 52 }
    if !'\u{7f}'.is_control() || !'\u{9f}'.is_control() || '\u{a0}'.is_control() { return 53 }
    if !'\u{e9}'.is_alphabetic() || !'\u{4e2d}'.is_alphabetic() || '1'.is_alphabetic() { return 54 }
    if !'\u{663}'.is_numeric() || !'\u{bd}'.is_numeric() || 'x'.is_numeric() { return 55 }
    if !'\u{e9}'.is_alphanumeric() || !'7'.is_alphanumeric() || '!'.is_alphanumeric() { return 56 }
    if !'\u{e9}'.is_lowercase() || '\u{c9}'.is_lowercase() { return 57 }
    if !'\u{c9}'.is_uppercase() || '\u{e9}'.is_uppercase() { return 58 }
    if !'\u{df}'.is_lowercase() || '\u{4e2d}'.is_lowercase() { return 59 }
    0
}

fn checks_case_mapping(): i32 {
    if 'A'.to_ascii_lowercase() != 'a' || 'a'.to_ascii_uppercase() != 'A' { return 60 }
    if '\u{e9}'.to_ascii_uppercase() != '\u{e9}' || '1'.to_ascii_lowercase() != '1' { return 61 }
    if !'A'.eq_ignore_ascii_case('a') || 'a'.eq_ignore_ascii_case('b') { return 62 }
    if '\u{c9}'.eq_ignore_ascii_case('\u{e9}') { return 63 }
    var upper = 'a'
    upper.make_ascii_uppercase()
    if upper != 'A' { return 64 }
    var lower = 'Q'
    lower.make_ascii_lowercase()
    if lower != 'q' { return 65 }
    var unchanged = '\u{e9}'
    unchanged.make_ascii_uppercase()
    if unchanged != '\u{e9}' { return 66 }

    var lowered = '\u{c9}'.to_lowercase()
    if !char_is(lowered.next(), '\u{e9}') { return 67 }
    if lowered.next().is_present() { return 69 }

    var sharp = '\u{df}'.to_uppercase()
    if !char_is(sharp.next(), 'S') { return 70 }
    if !char_is(sharp.next(), 'S') { return 72 }
    if sharp.next().is_present() { return 74 }

    var dotted = '\u{130}'.to_lowercase()
    if !char_is(dotted.next(), 'i') { return 75 }
    if !char_is(dotted.next(), '\u{307}') { return 77 }
    if dotted.next().is_present() { return 79 }
    0
}

fn checks_lengths_and_encoding(): i32 {
    if 'a'.len_utf8() != 1usize || '\u{e9}'.len_utf8() != 2usize { return 80 }
    if '\u{800}'.len_utf8() != 3usize || '\u{ffff}'.len_utf8() != 3usize { return 81 }
    if '\u{10000}'.len_utf8() != 4usize || '\u{10ffff}'.len_utf8() != 4usize { return 82 }
    if 'a'.len_utf16() != 1usize || '\u{ffff}'.len_utf16() != 1usize { return 83 }
    if '\u{10000}'.len_utf16() != 2usize || '\u{10ffff}'.len_utf16() != 2usize { return 84 }

    var units = [0u16; 2]
    let single = '\u{e9}'.encode_utf16(mut units)
    if single.len() != 1usize || single[0usize] != 0xe9u16 { return 85 }
    let pair = '\u{1f600}'.encode_utf16(mut units)
    if pair.len() != 2usize || pair[0usize] != 0xd83du16 || pair[1usize] != 0xde00u16 { return 86 }
    0
}

fn checks_escapes(): i32 {
    if escape_text('\n'.escape_default()).as_text() != "\\n" { return 90 }
    if escape_text('\t'.escape_default()).as_text() != "\\t" { return 91 }
    if escape_text('\r'.escape_default()).as_text() != "\\r" { return 92 }
    if escape_text('\0'.escape_default()).as_text() != "\\u{0}" { return 93 }
    if escape_text('\0'.escape_debug()).as_text() != "\\0" { return 115 }
    if escape_text('\\'.escape_default()).as_text() != "\\\\" { return 94 }
    if escape_text('\''.escape_default()).as_text() != "\\'" { return 95 }
    if escape_text('a'.escape_default()).as_text() != "a" { return 96 }
    if escape_text('\u{e9}'.escape_default()).as_text() != "\\u{e9}" { return 97 }
    if escape_text('\u{1f600}'.escape_default()).as_text() != "\\u{1f600}" { return 98 }
    if escape_text('\u{7f}'.escape_default()).as_text() != "\\u{7f}" { return 99 }
    if escape_text('\u{1f}'.escape_default()).as_text() != "\\u{1f}" { return 100 }
    if escape_text('a'.escape_unicode()).as_text() != "\\u{61}" { return 101 }
    if escape_text('\0'.escape_unicode()).as_text() != "\\u{0}" { return 102 }
    if escape_text('\u{10ffff}'.escape_unicode()).as_text() != "\\u{10ffff}" { return 103 }
    if escape_text('\u{e9}'.escape_debug()).as_text() != "\u{e9}" { return 104 }
    if escape_text('\u{7f}'.escape_debug()).as_text() != "\\u{7f}" { return 105 }
    if escape_text('\n'.escape_debug()).as_text() != "\\n" { return 106 }
    if escape_text('\''.escape_debug()).as_text() != "\\'" { return 107 }
    if escape_text('"'.escape_debug()).as_text() != "\\\"" { return 108 }
    if escape_text('"'.escape_default()).as_text() != "\\\"" { return 109 }
    0
}

fn main(): i32 {
    let first = checks_construction()
    if first != 0 { return first }
    let second = checks_digits()
    if second != 0 { return second }
    let third = checks_ascii_predicates()
    if third != 0 { return third }
    let fourth = checks_unicode_predicates()
    if fourth != 0 { return fourth }
    let fifth = checks_case_mapping()
    if fifth != 0 { return fifth }
    let sixth = checks_lengths_and_encoding()
    if sixth != 0 { return sixth }
    checks_escapes()
}
