import core.iter.BidirectionalIterator
import core.iter.Iterator
import core.text
import alloc.string

fn main(): i32 {
    let text = "a\u{e9}-b\u{e9}-"
    match text.rfind("\u{e9}") {
        present(index) => { if index != 5usize { return 1 } },
        none => { return 1 }
    }
    match text.rfind("") {
        present(index) => { if index != text.len() { return 2 } },
        none => { return 2 }
    }
    if text.is_ascii() || " \t\u{e9} \n".trim_ascii() != "\u{e9}" { return 17 }
    if " \t x \n".trim_ascii() != "x" { return 18 }
    match text.rsplit_once("\u{e9}") {
        present(parts) => { if parts.0 != "a\u{e9}-b" || parts.1 != "-" { return 3 } },
        none => { return 3 }
    }
    var matches = "one\u{e9}one".matches("one")
    match matches.next() {
        present(piece) => { if piece != "one" { return 22 } },
        none => { return 22 }
    }
    match matches.next() {
        present(piece) => { if piece != "one" { return 23 } },
        none => { return 23 }
    }
    match matches.next() { present(_) => { return 24 }, none => {} }
    var match_indices = "one\u{e9}one".match_indices("one")
    match match_indices.next() {
        present(item) => { if item.0 != 0usize || item.1 != "one" { return 25 } },
        none => { return 25 }
    }
    match match_indices.next() {
        present(item) => { if item.0 != 5usize || item.1 != "one" { return 26 } },
        none => { return 26 }
    }
    var reverse_indices = "one\u{e9}one".rmatch_indices("one")
    match reverse_indices.next() {
        present(item) => { if item.0 != 5usize { return 27 } },
        none => { return 27 }
    }
    match reverse_indices.next() {
        present(item) => { if item.0 != 0usize || item.1 != "one" { return 48 } },
        none => { return 48 }
    }
    if reverse_indices.next().is_present() || match_indices.next().is_present() { return 49 }
    var reverse_matches = "one\u{e9}one".rmatches("one")
    match reverse_matches.next() {
        present(piece) => { if piece != "one" { return 28 } },
        none => { return 28 }
    }
    match reverse_matches.next() {
        present(piece) => { if piece != "one" { return 50 } },
        none => { return 50 }
    }
    if reverse_matches.next().is_present() { return 51 }
    let trimmed = ".. \u{e9}x \n..".trim_start_matches(".").trim_start().trim_end_matches(".").trim_end()
    if trimmed != "\u{e9}x" { return 29 }
    if "..x..".trim_start_matches(".") != "x.." ||
        "..x..".trim_end_matches(".") != "..x" {
        return 41
    }
    var words = " one \u{e9} two ".split_whitespace()
    match words.next() { present(word) => { if word != "one" { return 30 } }, none => { return 30 } }
    match words.next() { present(word) => { if word != "\u{e9}" { return 31 } }, none => { return 31 } }
    match words.next() { present(word) => { if word != "two" { return 31 } }, none => { return 31 } }
    var encoded = "a\u{1f600}".encode_utf16()
    match encoded.next() { present(unit) => { if unit != 0x61u16 { return 32 } }, none => { return 32 } }
    match encoded.next() { present(unit) => { if unit != 0xd83du16 { return 33 } }, none => { return 33 } }
    match encoded.next() { present(unit) => { if unit != 0xde00u16 { return 34 } }, none => { return 34 } }
    var escaped = alloc.string.new()
    var escape_chars = "\n\u{e9}".escape_debug()
    while true {
        match escape_chars.next() {
            present(c) => { escaped.push(c) },
            none => { break }
        }
    }
    if escaped.as_text() != "\\n\u{e9}" { return 35 }
    escaped.clear()
    var default_escape = "\u{1f600}".escape_default()
    while true {
        match default_escape.next() {
            present(c) => { escaped.push(c) },
            none => { break }
        }
    }
    if escaped.as_text() != "\\u{1f600}" { return 42 }
    escaped.clear()
    var unicode_escape = '\u{1f600}'.escape_unicode()
    while true {
        match unicode_escape.next() {
            present(c) => { escaped.push(c) },
            none => { break }
        }
    }
    if escaped.as_text() != "\\u{1f600}" { return 43 }

    match core.char.from_digit(35u32, 36u32) {
        present(c) => { if c != 'z' { return 36 } },
        none => { return 36 }
    }
    if core.char.from_digit(36u32, 36u32).is_present() ||
        core.char.from_digit(1u32, 1u32).is_present() {
        return 45
    }
    var units = [0u16; 2]
    let utf16 = '\u{1f600}'.encode_utf16(mut units[0usize..2usize])
    if utf16.len() != 2usize || utf16[0usize] != 0xd83du16 ||
        utf16[1usize] != 0xde00u16 { return 37 }
    var lower = 'A'
    lower.make_ascii_lowercase()
    if lower != 'a' { return 38 }
    var upper = 'z'
    upper.make_ascii_uppercase()
    if upper != 'Z' { return 44 }
    var char_escapes = '\n'.escape_default()
    match char_escapes.next() { present(c) => { if c != '\\' { return 39 } }, none => { return 39 } }
    match char_escapes.next() { present(c) => { if c != 'n' { return 40 } }, none => { return 40 } }
    var debug_escape = '\u{1f600}'.escape_debug()
    match debug_escape.next() {
        present(c) => { if c != '\u{1f600}' { return 46 } },
        none => { return 46 }
    }
    match debug_escape.next() { none => {}, present(_) => { return 47 } }

    var chars = text.chars()
    match chars.next() { present(c) => { if c != 'a' { return 4 } }, none => { return 4 } }
    match chars.next_back() { present(c) => { if c != '-' { return 5 } }, none => { return 5 } }
    match chars.next_back() { present(c) => { if c != '\u{e9}' { return 6 } }, none => { return 6 } }
    var indices = text.char_indices()
    match indices.next_back() {
        present(pair) => { if pair.0 != 7usize || pair.1 != '-' { return 7 } },
        none => { return 7 }
    }
    match indices.next() {
        present(pair) => { if pair.0 != 0usize || pair.1 != 'a' { return 8 } },
        none => { return 8 }
    }
    var bytes = text.bytes()
    match bytes.next() { present(byte) => { if byte != 0x61u8 { return 9 } }, none => { return 9 } }
    match bytes.next_back() { present(byte) => { if byte != 0x2du8 { return 10 } }, none => { return 10 } }

    var pieces = "a,b,c".split(',')
    match pieces.next() { present(piece) => { if piece != "a" { return 11 } }, none => { return 11 } }
    match pieces.next_back() { present(piece) => { if piece != "c" { return 12 } }, none => { return 12 } }
    match pieces.next() { present(piece) => { if piece != "b" { return 13 } }, none => { return 13 } }
    match pieces.next_back() { present(_) => { return 14 }, none => {} }
    var reverse_pieces = "a,b,c".rsplit(",")
    match take reverse_pieces.next() {
        present(piece) => { if piece != "c" { return 19 } },
        none => { return 19 }
    }

    var valid_bytes = [0xc3u8, 0xa9u8]
    match take core.text.from_utf8_mut(mut valid_bytes) {
        success(view) => { if view.len() != 2usize || view != "\u{e9}" { return 20 } },
        failure(_) => { return 20 }
    }
    var invalid_bytes = [0xc3u8]
    match take core.text.from_utf8_mut(mut invalid_bytes) {
        success(_) => { return 21 },
        failure(error) => {
            if error.valid_up_to() != 0usize || error.error_len().is_present() { return 21 }
        }
    }

    let replaced = text.replace("\u{e9}", "o")
    if replaced.as_text() != "ao-bo-" { return 15 }
    let limited = text.replacen("", "|", 2usize)
    if limited.as_text() != "|a|\u{e9}-b\u{e9}-" { return 16 }
    0
}
