import alloc.string.String;
import package.core.cmp.Ord;
import alloc.vec.Vec;

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
