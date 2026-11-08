// profiles: debug release
// Evidence for V1 str (Text) operations that other text tests do not cover:
// size and scalar boundaries, borrowed splitting, validated and unchecked
// UTF-8 construction, iterator double-ended and as_str behaviour, comparison,
// range indexing, case mapping, and parsing.

import core.option
import core.text.{Text, from_utf8, from_utf8_mut, from_utf8_unchecked}
import core.cmp.Ordering
import alloc.string

fn checks_size_and_boundaries(): i32 {
    if !"".is_empty() || "abc".is_empty() { return 1 }
    if "abc".len() != 3usize || "\u{e9}".len() != 2usize { return 2 }
    if !"abc".is_ascii() || "\u{e9}".is_ascii() { return 3 }
    if "\u{e9}".as_bytes()[0usize] != 0xc3u8 { return 4 }
    let accented = "\u{e9}"
    if accented.is_char_boundary(0usize) != true || accented.is_char_boundary(1usize) { return 5 }
    if !accented.is_char_boundary(2usize) || accented.is_char_boundary(3usize) { return 6 }
    if accented.floor_char_boundary(1usize) != 0usize { return 7 }
    if accented.ceil_char_boundary(1usize) != 2usize { return 8 }
    if accented.floor_char_boundary(99usize) != 2usize || accented.ceil_char_boundary(99usize) != 2usize { return 9 }
    let mixed = "a\u{e9}"
    if mixed.get(1usize, 2usize).is_present() { return 10 }
    if !text_is(mixed.get(1usize, 3usize), "\u{e9}") { return 11 }
    if mixed.get(3usize, 1usize).is_present() || mixed.get(0usize, 4usize).is_present() { return 12 }
    if !text_is(mixed.get(0usize, 3usize), "a\u{e9}") { return 13 }
    0
}

fn text_is(value: (read Text)?, expected: read Text): bool {
    match value {
        present(found) => found == expected,
        none => false
    }
}

fn checks_split_at(): i32 {
    let word = "a\u{e9}b"
    let parts = word.split_at(1usize)
    if parts.0 != "a" || parts.1 != "\u{e9}b" { return 20 }
    let after = word.split_at(3usize)
    if after.0 != "a\u{e9}" || after.1 != "b" { return 21 }
    if word.split_at_checked(2usize).is_present() { return 22 }
    match word.split_at_checked(4usize) {
        present(pair) => { if pair.0 != "a\u{e9}b" || pair.1 != "" { return 23 } },
        none => { return 24 }
    }
    if word.split_at_checked(9usize).is_present() { return 25 }
    if word.find_byte(0x62u8) != present(3usize) || word.find_byte(0u8).is_present() { return 26 }
    0
}

fn checks_iterators(): i32 {
    var chars = "a\u{e9}".chars()
    match chars.next_back() {
        present(c) => { if c != '\u{e9}' { return 30 } },
        none => { return 31 }
    }
    match chars.next() {
        present(c) => { if c != 'a' { return 32 } },
        none => { return 33 }
    }
    if chars.next().is_present() || chars.next_back().is_present() { return 34 }

    var stepped = "abc".chars()
    match stepped.next() {
        present(_) => {},
        none => { return 35 }
    }
    if stepped.as_str() != "bc" { return 36 }

    var indices = "\u{e9}\u{1f600}".char_indices()
    match indices.next() {
        present(item) => { if item.0 != 0usize || item.1 != '\u{e9}' { return 37 } },
        none => { return 38 }
    }
    match indices.next_back() {
        present(item) => { if item.0 != 2usize || item.1 != '\u{1f600}' { return 39 } },
        none => { return 40 }
    }
    if indices.offset() != 2usize { return 41 }

    var bytes = "\u{e9}".bytes()
    if bytes.next() != present(0xc3u8) { return 42 }
    if bytes.next_back() != present(0xa9u8) { return 43 }
    if bytes.next().is_present() { return 44 }

    var lines = "a\nb\r\nc".lines()
    if !text_is(lines.next(), "a") || !text_is(lines.next(), "b") || !text_is(lines.next(), "c") { return 45 }
    if lines.next().is_present() { return 46 }
    var trailing = "a\n".lines()
    if !text_is(trailing.next(), "a") || trailing.next().is_present() { return 47 }
    var empty_line = "a\n\nb".lines()
    if !text_is(empty_line.next(), "a") || !text_is(empty_line.next(), "") { return 48 }
    if !text_is(empty_line.next(), "b") { return 49 }
    0
}

fn checks_from_utf8(): i32 {
    let valid = [0x61u8, 0xc3u8, 0xa9u8]
    if !text_is(from_utf8(read valid), "a\u{e9}") { return 50 }
    if from_utf8(read [0xffu8]).is_present() { return 51 }
    if from_utf8(read [0xc0u8, 0x80u8]).is_present() { return 52 }
    if from_utf8(read [0xedu8, 0xa0u8, 0x80u8]).is_present() { return 53 }
    if from_utf8(read [0xe9u8]).is_present() { return 54 }
    if from_utf8(read [0x80u8]).is_present() { return 55 }
    if from_utf8(read [0xf4u8, 0x90u8, 0x80u8, 0x80u8]).is_present() { return 56 }
    if !text_is(from_utf8(read [0xf4u8, 0x8fu8, 0xbfu8, 0xbfu8]), "\u{10ffff}") { return 57 }
    var mutable = [0x61u8, 0xc3u8, 0xa9u8]
    match from_utf8_mut(mut mutable) {
        present(view) => { if view != "a\u{e9}" { return 58 } },
        none => { return 59 }
    }
    if from_utf8_mut(mut [0xffu8]).is_present() { return 60 }
    let direct = unsafe { from_utf8_unchecked(read valid) }
    if direct != "a\u{e9}" { return 61 }
    0
}

fn checks_comparison_and_ranges(): i32 {
    if !("a" < "b") || "b" < "a" { return 70 }
    if !("\u{e9}" > "z") { return 69 }
    if "a".cmp("b") != Ordering.Less || "b".cmp("a") != Ordering.Greater { return 71 }
    if "ab".cmp("ab") != Ordering.Equal { return 72 }
    match "ab".partial_cmp("abc") {
        present(order) => { if order != Ordering.Less { return 73 } },
        none => { return 74 }
    }
    let text = "abc"
    let head = read text[0usize..2usize]
    let empty_middle = read text[1usize..1usize]
    if !text_is(present(head), "ab") || !text_is(present(empty_middle), "") { return 75 }
    0
}

fn checks_case_and_repetition(): i32 {
    if "\u{39f}\u{394}\u{39f}\u{3a3}".to_lowercase().as_text() != "\u{3bf}\u{3b4}\u{3bf}\u{3c2}" { return 80 }
    if "\u{df}".to_uppercase().as_text() != "SS" { return 81 }
    if "\u{130}".to_lowercase().as_text() != "i\u{307}" { return 82 }
    if "A\u{62}\u{c9}".to_ascii_lowercase().as_text() != "ab\u{c9}" { return 83 }
    if "a\u{e9}".to_ascii_uppercase().as_text() != "A\u{e9}" { return 84 }
    if !"Hello".eq_ignore_ascii_case("hELLO") || "\u{e9}".eq_ignore_ascii_case("\u{c9}") { return 85 }
    var upper = "Ab".uppercase_chars()
    if upper.next() != present('A') || upper.next() != present('B') || upper.next().is_present() { return 86 }
    var lower = "A\u{130}".lowercase_chars()
    if lower.next() != present('a') { return 87 }
    if "ab".repeat(3usize).as_text() != "ababab" || "x".repeat(0usize).as_text() != "" { return 88 }
    if "a.b.c".replace(".", "::").as_text() != "a::b::c" { return 89 }
    if "a.b.c".replacen(".", "-", 1usize).as_text() != "a-b.c" { return 90 }
    if "abc".replace("", "-").as_text() != "-a-b-c-" { return 91 }
    0
}

fn checks_parse(): i32 {
    match capture "2.5".parse<f64>() {
        success(value) => { if value != 2.5f64 { return 95 } },
        failure(_) => { return 96 }
    }
    match capture "not a number".parse<f64>() {
        success(_) => { return 97 },
        failure(_) => {}
    }
    0
}

fn main(): i32 {
    let first = checks_size_and_boundaries()
    if first != 0 { return first }
    let second = checks_split_at()
    if second != 0 { return second }
    let third = checks_iterators()
    if third != 0 { return third }
    let fourth = checks_from_utf8()
    if fourth != 0 { return fourth }
    let fifth = checks_comparison_and_ranges()
    if fifth != 0 { return fifth }
    let sixth = checks_case_and_repetition()
    if sixth != 0 { return sixth }
    checks_parse()
}
