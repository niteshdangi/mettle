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

    var pieces = "a,b,c".split(",")
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
    match core.text.from_utf8_mut(mut valid_bytes) {
        present(view) => { if view.len() != 2usize { return 20 } },
        none => { return 20 }
    }
    var invalid_bytes = [0xc3u8]
    match core.text.from_utf8_mut(mut invalid_bytes) {
        present(_) => { return 21 },
        none => {}
    }

    let replaced = text.replace("\u{e9}", "o")
    if replaced.as_text() != "ao-bo-" { return 15 }
    let limited = text.replacen("", "|", 2usize)
    if limited.as_text() != "|a|\u{e9}-b\u{e9}-" { return 16 }
    0
}
