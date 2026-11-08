// profiles: debug release
// Evidence for String::retain (in-place compaction over multi-byte scalars,
// including removing every scalar and keeping none) and the owned lossy
// conversion String::from_utf8_lossy_owned.

import alloc.string.{String, from_utf8_lossy_owned}
import alloc.vec
import core.option

fn checks_retain(): i32 {
    var s = String("a\u{e9}b\u{1f600}c")
    s.retain(fn(c: char): bool { c != '\u{e9}' && c != '\u{1f600}' })
    if s.as_text() != "abc" || s.len() != 3usize { return 1 }

    var all = String("\u{e9}\u{1f600}")
    all.retain(fn(c: char): bool { true })
    if all.as_text() != "\u{e9}\u{1f600}" { return 2 }

    var none_kept = String("\u{e9}x")
    none_kept.retain(fn(c: char): bool { false })
    if !none_kept.is_empty() { return 3 }

    var counted = 0usize
    var keep_ascii = String("x\u{e9}y")
    keep_ascii.retain(fn(c: char): bool {
        counted += 1usize
        c.is_ascii()
    })
    if keep_ascii.as_text() != "xy" || counted != 3usize { return 4 }
    0
}

fn checks_lossy_owned(): i32 {
    var bytes = vec.new<u8>()
    bytes.push(0x61u8)
    bytes.push(0xffu8)
    bytes.push(0x62u8)
    let text = from_utf8_lossy_owned(take bytes)
    if text.as_text() != "a\u{fffd}b" { return 10 }
    var valid = vec.new<u8>()
    valid.push(0xc3u8)
    valid.push(0xa9u8)
    if from_utf8_lossy_owned(take valid).as_text() != "\u{e9}" { return 11 }
    0
}

fn main(): i32 {
    let first = checks_retain()
    if first != 0 { return first }
    checks_lossy_owned()
}
