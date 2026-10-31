import alloc.string

fn main(): i32 {
    var text = string.from_text("a\u{e9}b")
    if text.floor_char_boundary(0usize) != 0usize { return 1 }
    if text.floor_char_boundary(2usize) != 1usize { return 2 }
    if text.ceil_char_boundary(2usize) != 3usize { return 3 }
    if text.ceil_char_boundary(99usize) != text.len() { return 4 }
    if text.repeat(2usize).as_text() != "a\u{e9}ba\u{e9}b" { return 5 }

    text.retain(fn(ch: char): bool { ch != '\u{e9}' })
    if text.as_text() != "ab" { return 6 }

    var spaces = string.from_text("a b")
    spaces.retain(fn(ch: char): bool { ch != ' ' })
    if spaces.as_text() != "ab" { return 7 }

    var empty = string.from_text("")
    empty.retain(fn(ch: char): bool { ch == ch })
    if !empty.is_empty() { return 8 }

    let leaked = string.from_text("kept").leak()
    if leaked != "kept" { return 9 }
    0
}
