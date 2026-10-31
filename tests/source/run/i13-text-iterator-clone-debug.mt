import core.fmt
import core.fmt.Debug
import core.fmt.Spec
import core.iter.ExactSizeIterator
import core.clone.Clone

fn render_chars(): i32 throws fmt.Error {
    let chars = "bc".chars()
    var bytes = [0u8; 64]
    var output = fmt.buffer_writer(mut bytes)
    let options = Spec(' ', fmt.Align.Unknown, none, none, false, true, false, false)
    var f = fmt.formatter(mut output, options)
    try chars.fmt(mut f)
    let length = output.len()
    match fmt.written_text(read bytes, length) {
        present(text) => { if text != "Chars { remaining: \"bc\" }" { return 1 } },
        none => { return 1 }
    }
    0
}

fn main(): i32 {
    var chars = "abc".chars()
    match chars.next() {
        present(c) => { if c != 'a' { return 1 } },
        none => { return 1 }
    }
    var copy = chars.clone()
    match chars.next() { present(_) => {}, none => { return 2 } }
    if chars.as_str() != "c" || copy.as_str() != "bc" { return 3 }
    match copy.next_back() {
        present(c) => { if c != 'c' { return 4 } },
        none => { return 4 }
    }

    var bytes = "abc".bytes()
    if bytes.len() != 3usize { return 5 }
    match bytes.next() { present(_) => {}, none => { return 5 } }
    var more = bytes.clone()
    match bytes.next() { present(_) => {}, none => { return 5 } }
    if bytes.len() != 1usize || more.len() != 2usize { return 6 }

    var parts = "a,b,c".split(",")
    match parts.next() { present(_) => {}, none => { return 7 } }
    var parts_copy = parts.clone()
    match parts.next() { present(_) => {}, none => { return 7 } }
    match parts_copy.next() {
        present(piece) => { if piece != "b" { return 8 } },
        none => { return 8 }
    }

    var words = " x  y ".split_whitespace()
    var words_copy = words.clone()
    match words.next() { present(_) => {}, none => { return 9 } }
    match words_copy.next() {
        present(word) => { if word != "x" { return 9 } },
        none => { return 9 }
    }

    var indices = "h\u{e9}".char_indices()
    var indices_copy = indices.clone()
    match indices.next() { present(_) => {}, none => { return 10 } }
    match indices_copy.next() {
        present(item) => { if item.0 != 0usize || item.1 != 'h' { return 10 } },
        none => { return 10 }
    }

    var lines = "a\nb".lines()
    var lines_copy = lines.clone()
    match lines.next() { present(_) => {}, none => { return 11 } }
    match lines_copy.next() {
        present(line) => { if line != "a" { return 11 } },
        none => { return 11 }
    }

    match take capture render_chars() {
        success(code) => code,
        failure(_) => 99
    }
}
