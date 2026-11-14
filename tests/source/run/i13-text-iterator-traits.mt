// profiles: debug release

import alloc.string.String
import core.clone.Clone
import core.borrow.ToOwned
import core.fmt
import core.fmt.Debug
import core.iter.{Iterator, ExactSizeIterator}
import core.text.{FromStr, Text}
import core.option
import core.panic.panic

fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => panic("iterator formatting failed")
    }
    output
}

fn rejects_full_writer<T: Debug>(read value: T): bool {
    var storage: [u8; 0] = []
    var output = fmt.buffer_writer(mut storage)
    var formatter = fmt.formatter(mut output, fmt.spec())
    (capture value.fmt(mut formatter)).is_failure()
}

fn main(): i32 {
    var chars = "a\u{e9}".chars()
    if chars.len() != 2usize { return 1 }
    var cloned_chars = chars.clone()
    if cloned_chars.next_back() != present('\u{e9}') { return 2 }
    if chars.next() != present('a') || chars.len() != 1usize { return 3 }
    if !debug_text(chars).contains("\u{e9}") || !rejects_full_writer(chars) { return 4 }
    var owned_chars = chars.to_owned()
    if owned_chars.next() != present('\u{e9}') || chars.next_back() != present('\u{e9}') ||
        cloned_chars.next() != present('a') { return 27 }

    var indices = "a\u{e9}".char_indices()
    var cloned_indices = indices.clone()
    if cloned_indices.next_back() != present((1usize, '\u{e9}')) { return 5 }
    if indices.next() != present((0usize, 'a')) || indices.len() != 1usize { return 6 }
    if !debug_text(indices).contains("\u{e9}") || !rejects_full_writer(indices) { return 7 }
    var owned_indices = indices.to_owned()
    if owned_indices.next_back() != present((1usize, '\u{e9}')) ||
        indices.next() != present((1usize, '\u{e9}')) { return 28 }

    var bytes = "ab".bytes()
    var cloned_bytes = bytes.clone()
    if cloned_bytes.next_back() != present(98u8) { return 8 }
    if bytes.len() != 2usize || bytes.next() != present(97u8) { return 9 }
    if !debug_text(bytes).contains("98") || !rejects_full_writer(bytes) { return 10 }
    var owned_bytes = bytes.to_owned()
    if owned_bytes.next_back() != present(98u8) || bytes.next() != present(98u8) ||
        owned_bytes.next().is_present() { return 29 }

    var split = "a,b,c".split(',')
    var cloned_split = split.clone()
    match cloned_split.next() {
        present(part) => { if part != "a" { return 11 } },
        none => { return 11 }
    }
    match split.next_back() {
        present(part) => { if part != "c" { return 11 } },
        none => { return 11 }
    }
    if !debug_text(split).contains("a,b") || !rejects_full_writer(split) { return 12 }
    var owned_split = split.to_owned()
    if owned_split.next_back() != present("b") || split.next() != present("a") ||
        owned_split.next() != present("a") || split.next_back() != present("b") { return 30 }

    var words = " a  b ".split_whitespace()
    var cloned_words = words.clone()
    match cloned_words.next_back() {
        present(word) => { if word != "b" { return 13 } },
        none => { return 13 }
    }
    match words.next() {
        present(word) => { if word != "a" { return 13 } },
        none => { return 13 }
    }
    if !debug_text(words).contains("b") || !rejects_full_writer(words) { return 14 }
    var owned_words = words.to_owned()
    if owned_words.next() != present("b") || words.next_back() != present("b") ||
        owned_words.next_back().is_present() { return 31 }

    var reverse_matches = "a,b,c".rmatches(',')
    if reverse_matches.next() != present(",") { return 32 }
    var reverse_matches_copy = reverse_matches.clone()
    if reverse_matches.next() != present(",") || reverse_matches_copy.next() != present(",") ||
        reverse_matches.next().is_present() || reverse_matches_copy.next().is_present() { return 33 }

    var match_indices = "a,b,c".match_indices(',')
    if match_indices.next() != present((1usize, ",")) { return 34 }
    var match_indices_copy = match_indices.clone()
    if match_indices.next() != present((3usize, ",")) ||
        match_indices_copy.next() != present((3usize, ",")) { return 35 }

    var reverse_match_indices = "a,b,c".rmatch_indices(',')
    if reverse_match_indices.next() != present((3usize, ",")) { return 36 }
    var reverse_match_indices_copy = reverse_match_indices.clone()
    if reverse_match_indices.next() != present((1usize, ",")) ||
        reverse_match_indices_copy.next() != present((1usize, ",")) { return 37 }

    var matches = "a,b,c".matches(',')
    if matches.next() != present(",") { return 38 }
    var matches_copy = matches.clone()
    if matches.next() != present(",") || matches_copy.next() != present(",") { return 39 }

    var limited_split = "a,b,c".splitn(3usize, ",")
    if limited_split.next() != present("a") { return 40 }
    var limited_split_copy = limited_split.clone()
    if limited_split.next() != present("b") || limited_split_copy.next() != present("b") { return 41 }

    var limited_reverse_split = "a,b,c".rsplitn(3usize, ",")
    if limited_reverse_split.next() != present("c") { return 42 }
    var limited_reverse_split_copy = limited_reverse_split.clone()
    if limited_reverse_split.next() != present("b") ||
        limited_reverse_split_copy.next() != present("b") { return 43 }

    var terminated_split = "a,b,".split_terminator(",")
    if terminated_split.next() != present("a") { return 44 }
    var terminated_split_copy = terminated_split.clone()
    if terminated_split.next() != present("b") || terminated_split_copy.next() != present("b") { return 45 }

    var reverse_terminated_split = "a,b,".rsplit_terminator(",")
    if reverse_terminated_split.next() != present("b") { return 46 }
    var reverse_terminated_split_copy = reverse_terminated_split.clone()
    if reverse_terminated_split.next() != present("a") ||
        reverse_terminated_split_copy.next() != present("a") { return 47 }

    var lines = "first\nsecond\n".lines()
    if lines.next() != present("first") { return 48 }
    var lines_copy = lines.clone()
    if lines.next() != present("second") || lines_copy.next() != present("second") { return 49 }

    var utf16 = "A🦀".encode_utf16()
    if utf16.next() != present(65u16) { return 50 }
    var utf16_copy = utf16.clone()
    if utf16.next() != present(0xd83eu16) || utf16_copy.next() != present(0xd83eu16) { return 51 }
    if utf16.next() != present(0xdd80u16) || utf16_copy.next() != present(0xdd80u16) { return 52 }

    if "(body".strip_circumfix("(", ")").is_present() { return 15 }
    match "(body)".strip_circumfix("(", ")") {
        present(body) => { if body != "body" { return 16 } },
        none => { return 17 }
    }
    let source = "a\u{e9}b"
    let part = match source.get(1usize, 3usize) {
        present(part) => part,
        none => { return 19 }
    }
    match source.substr_range(part) {
        present(range) => {
            if range.start != 1usize || range.end != 3usize { return 18 }
        },
        none => { return 19 }
    }
    if source.get(2usize, 3usize).is_present() { return 20 }
    let foreign = String("\u{e9}")
    if source.substr_range(foreign.as_text()).is_present() { return 25 }
    let empty = read source[3usize..3usize]
    match source.substr_range(empty) {
        present(range) => {
            if range.start != 3usize || range.end != 3usize { return 26 }
        },
        none => { return 26 }
    }

    var mutable = String("a\u{e9}b")
    match mutable.as_mut_str().split_at_mut_checked(1usize) {
        present(parts) => {
            if parts.0 != "a" || parts.1 != "\u{e9}b" { return 21 }
        },
        none => { return 22 }
    }
    if mutable.as_mut_str().split_at_mut_checked(2usize).is_present() { return 23 }
    match capture String.(FromStr).from_str("parsed") {
        success(value) => { if value.as_text() != "parsed" { return 24 } },
    }
    0
}
