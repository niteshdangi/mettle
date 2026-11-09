// profiles: debug release

import alloc.string.String
import core.clone.Clone
import core.fmt
import core.fmt.Debug
import core.iter.{Iterator, ExactSizeIterator}
import core.text.{FromStr, Text}
import core.option

fn debug_text<T: Debug>(read value: T): String {
    var output = String("")
    var formatter = fmt.formatter(mut output, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(_) => {},
        failure(_) => {}
    }
    output
}

fn main(): i32 {
    var chars = "a\u{e9}".chars()
    if chars.len() != 2usize { return 1 }
    var cloned_chars = chars.clone()
    if cloned_chars.next_back() != present('\u{e9}') { return 2 }
    if chars.next() != present('a') || chars.len() != 1usize { return 3 }
    if debug_text(chars).is_empty() { return 4 }

    var indices = "a\u{e9}".char_indices()
    var cloned_indices = indices.clone()
    if cloned_indices.next_back() != present((1usize, '\u{e9}')) { return 5 }
    if indices.next() != present((0usize, 'a')) || indices.len() != 1usize { return 6 }
    if debug_text(indices).is_empty() { return 7 }

    var bytes = "ab".bytes()
    var cloned_bytes = bytes.clone()
    if cloned_bytes.next_back() != present(98u8) { return 8 }
    if bytes.len() != 2usize || bytes.next() != present(97u8) { return 9 }
    if debug_text(bytes).is_empty() { return 10 }

    var split = "a,b,c".split(",")
    var cloned_split = split.clone()
    match cloned_split.next() {
        present(part) => { if part != "a" { return 11 } },
        none => { return 11 }
    }
    match split.next_back() {
        present(part) => { if part != "c" { return 11 } },
        none => { return 11 }
    }
    if debug_text(split).is_empty() { return 12 }

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
    if debug_text(words).is_empty() { return 14 }

    if "(body".strip_circumfix("(", ")").is_present() { return 15 }
    match "(body)".strip_circumfix("(", ")") {
        present(body) => { if body != "body" { return 16 } },
        none => { return 17 }
    }
    match "a\u{e9}b".substr_range(1usize..3usize) {
        present(part) => { if part != "\u{e9}" { return 18 } },
        none => { return 19 }
    }
    if "a\u{e9}b".substr_range(2usize..3usize).is_present() { return 20 }

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
