import alloc.string

fn main(): i32 {
    let text = "a\u{e9}b"
    let middle = unsafe { text.get_unchecked(1usize, 3usize) }
    if middle != "\u{e9}" { return 1 }
    let whole = unsafe { text.get_unchecked(0usize, text.len()) }
    if whole != text { return 2 }
    let empty = unsafe { text.get_unchecked(3usize, 3usize) }
    if !empty.is_empty() { return 3 }

    var owned = string.from_text("xy\u{e9}z")
    {
        let tail = unsafe { owned.get_unchecked(2usize, 4usize) }
        if tail != "\u{e9}" { return 4 }
    }
    {
        var part = unsafe { owned.get_unchecked_mut(0usize, 2usize) }
        part.make_ascii_uppercase()
    }
    if owned.as_text() != "XY\u{e9}z" { return 5 }

    var literal = string.from_text("abc")
    {
        var tail = unsafe { literal.as_mut_str().get_unchecked_mut(1usize, 3usize) }
        tail.make_ascii_uppercase()
    }
    if literal.as_text() != "aBC" { return 6 }
    0
}
