import package.core.cmp.Ord
import alloc.vec.List

fn main(): i32 {
    var s = alloc.string.from_text("h\u{e9}llo")
    s.push(' ')
    s.push('\u{1F600}')
    s.push_str(" world")
    if s.len() != 17usize { return 1 }
    match s.pop() { present(ch) => { if ch != 'd' { return 2 } }, none => { return 3 } }
    s.insert(0usize, '\u{20ac}')
    if s.len() != 19usize || !s.as_text().starts_with("\u{20ac}h") { return 4 }
    if s.remove(0usize) != '\u{20ac}' { return 5 }
    s.truncate(7usize)
    if !(s.as_text() == "h\u{e9}llo ") { return 6 }
    let t = alloc.string.concat("ab", "cd")
    if !(t.as_text() == "abcd") { return 7 }
    let a = alloc.string.from_text("apple")
    let b = alloc.string.from_text("banana")
    if !a.cmp(b).is_lt() || a == b { return 8 }

    var reserved = alloc.string.with_capacity(4usize)
    if reserved.capacity() < 4usize { return 13 }
    reserved.reserve_exact(8usize)
    if reserved.capacity() < 8usize { return 14 }
    reserved.push_str("ok")
    reserved.shrink_to_fit()
    if reserved.capacity() < reserved.len() { return 15 }
    var prefix = alloc.string.from_text("a\u{e9}\u{1F600}b")
    let suffix = prefix.split_off(3usize)
    if !(prefix.as_text() == "a\u{e9}") || !(suffix.as_text() == "\u{1F600}b") {
        return 18
    }
    match capture alloc.string.try_with_capacity(8usize) {
        success(sized) => { if sized.capacity() < 8usize { return 16 } },
        failure(_) => { return 17 }
    }
    var changed = alloc.string.from_text("a\u{e9}bcd")
    changed.replace_range(1usize, 3usize, "X")
    if changed.as_text() != "aXbcd" { return 19 }
    changed.extend_from_within(1usize, 3usize)
    if changed.as_text() != "aXbcdXb" { return 20 }
    {
        var removed = changed.drain(1usize, 3usize)
        match removed.next() { present(c) => { if c != 'X' { return 21 } }, none => { return 21 } }
        match removed.next_back() { present(c) => { if c != 'b' { return 22 } }, none => { return 22 } }
    }
    if changed.as_text() != "acdXb" { return 23 }
    changed.shrink_to(2usize)
    if changed.capacity() < changed.len() || changed.capacity() < 2usize { return 24 }
    let whitespace = alloc.string.from_text(" one two ")
    var owned_words = whitespace.split_whitespace()
    match owned_words.next() { present(word) => { if word != "one" { return 90 } }, none => { return 90 } }
    match owned_words.next_back() { present(word) => { if word != "two" { return 91 } }, none => { return 91 } }

    let utf16_words = [0x61u16, 0xd83du16, 0xde00u16, 0x62u16]
    match capture alloc.string.from_utf16(utf16_words) {
        success(decoded) => { if decoded.as_text() != "a\u{1f600}b" { return 25 } },
        failure(_) => { return 25 }
    }
    let invalid_utf16 = [0xd800u16, 0x61u16]
    match capture alloc.string.from_utf16(invalid_utf16) {
        success(_) => { return 26 },
        failure(_) => {}
    }
    let lossy_utf16 = alloc.string.from_utf16_lossy(invalid_utf16)
    if lossy_utf16.as_text() != "\u{fffd}a" { return 27 }
    let invalid_utf8 = [0x61u8, 0xf0u8, 0x9fu8]
    let lossy_utf8 = alloc.string.from_utf8_lossy(invalid_utf8)
    if lossy_utf8.as_text() != "a\u{fffd}" { return 28 }

    var good = alloc.vec.new<u8>()
    good.push(0x68u8)
    good.push(0xc3u8)
    good.push(0xa9u8)
    match capture alloc.string.from_utf8(good) {
        success(g) => { if g.len() != 3usize { return 9 } },
        failure(_) => { return 10 }
    }
    var bad = alloc.vec.new<u8>()
    bad.push(0x68u8)
    bad.push(0xc3u8)
    let r = capture alloc.string.from_utf8(bad)
    match take r {
        success(_) => { return 11 },
        failure(e) => { if e.valid_up_to != 1usize || e.bytes.len() != 2usize { return 12 } }
    }
    0
}
