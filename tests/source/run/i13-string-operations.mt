// profiles: debug release
// Evidence for V1 owned String operations (alloc.string): construction,
// validated and lossy conversion, borrowing views, mutation, range removal
// and boundary behaviour, comparison, cloning and formatting.

import alloc.string.{String, from_utf8, from_utf8_lossy, from_utf16, from_utf16_lossy, concat}
import alloc.vec
import core.option
import core.text.Text
import core.iter.Iterator
import core.clone.Clone
import core.fmt.Write
import core.cmp.Ordering
import core.fmt

fn text_is(value: (read Text)?, read expected: Text): bool {
    match value {
        present(found) => found == expected,
        none => false
    }
}

fn checks_construction(): i32 {
    var empty = alloc.string.new()
    if !empty.is_empty() || empty.len() != 0usize { return 1 }
    let sized = alloc.string.with_capacity(16usize)
    if sized.capacity() < 16usize || !sized.is_empty() { return 2 }
    let copied = alloc.string.from_text("h\u{e9}")
    if copied.len() != 3usize || copied.as_text() != "h\u{e9}" { return 3 }
    let initialized = String("abc")
    if initialized.as_text() != "abc" { return 4 }
    let joined = concat("ab", "\u{e9}")
    if joined.as_text() != "ab\u{e9}" { return 5 }
    0
}

fn checks_validated_conversion(): i32 {
    var valid = vec.new<u8>()
    valid.push(0x61u8)
    valid.push(0xc3u8)
    valid.push(0xa9u8)
    match capture from_utf8(take valid) {
        success(s) => { if s.as_text() != "a\u{e9}" { return 10 } },
        failure(_) => { return 11 }
    }

    var invalid = vec.new<u8>()
    invalid.push(0x61u8)
    invalid.push(0xffu8)
    invalid.push(0x62u8)
    match capture from_utf8(take invalid) {
        success(_) => { return 12 },
        failure(error) => {
            if error.valid_up_to != 1usize { return 13 }
            if error.bytes.len() != 3usize { return 14 }
        }
    }

    let lossy = from_utf8_lossy([0x61u8, 0xffu8, 0x62u8])
    if lossy.as_text() != "a\u{fffd}b" { return 15 }
    let surrogate = from_utf8_lossy([0xedu8, 0xa0u8, 0x80u8])
    if surrogate.as_text() != "\u{fffd}\u{fffd}\u{fffd}" { return 16 }

    match capture from_utf16([0x61u16, 0xd83du16, 0xde00u16]) {
        success(s) => { if s.as_text() != "a\u{1f600}" { return 17 } },
        failure(_) => { return 18 }
    }
    match capture from_utf16([0x61u16, 0xd83du16]) {
        success(_) => { return 19 },
        failure(error) => { if error.index != 1usize || error.surrogate != 0xd83du16 { return 20 } }
    }
    match capture from_utf16([0xdc00u16]) {
        success(_) => { return 21 },
        failure(error) => { if error.index != 0usize { return 22 } }
    }
    let replaced = from_utf16_lossy([0xd83du16, 0x61u16, 0xdc00u16])
    if replaced.as_text() != "\u{fffd}a\u{fffd}" { return 23 }
    0
}

fn checks_views_and_bytes(): i32 {
    let text = String("ab\u{e9}")
    if text.as_bytes().len() != 4usize || text.as_bytes()[2usize] != 0xc3u8 { return 30 }
    let view = text.as_text()
    if view.len() != 4usize { return 31 }
    if text.len() != 4usize || text.capacity() < 4usize { return 32 }
    let owned = text.clone()
    if owned.as_text() != text.as_text() { return 33 }
    var list = text.into_bytes()
    if list.len() != 4usize { return 34 }
    let back = capture from_utf8(take list)
    match back {
        success(s) => { if s.as_text() != "ab\u{e9}" { return 35 } },
        failure(_) => { return 36 }
    }
    0
}

fn checks_mutation(): i32 {
    var s = String("ab")
    s.push('\u{e9}')
    if s.as_text() != "ab\u{e9}" { return 40 }
    s.push_str("cd")
    if s.as_text() != "ab\u{e9}cd" { return 41 }
    s.insert(0usize, 'X')
    if s.as_text() != "Xab\u{e9}cd" { return 42 }
    s.insert_str(1usize, "YZ")
    if s.as_text() != "XYZab\u{e9}cd" { return 43 }
    match s.pop() {
        present(c) => { if c != 'd' { return 44 } },
        none => { return 45 }
    }
    match s.pop() {
        present(c) => { if c != 'c' { return 46 } },
        none => { return 47 }
    }
    let removed = s.remove(3usize)
    if removed != 'a' { return 48 }
    if s.as_text() != "XYZb\u{e9}" { return 49 }
    s.truncate(4usize)
    if s.as_text() != "XYZb" { return 50 }
    s.truncate(10usize)
    if s.as_text() != "XYZb" { return 51 }
    var tail = s.split_off(2usize)
    if s.as_text() != "XY" || tail.as_text() != "Zb" { return 52 }
    s.clear()
    if !s.is_empty() { return 53 }
    match capture s.try_push_str("ok") {
        success(_) => {},
        failure(_) => { return 54 }
    }
    if s.as_text() != "ok" { return 55 }
    0
}

fn checks_ranges(): i32 {
    var s = String("h\u{e9}llo")
    s.replace_range(1usize, 3usize, "e")
    if s.as_text() != "hello" { return 60 }
    s.extend_from_within(0usize, 2usize)
    if s.as_text() != "hellohe" { return 61 }
    {
        var drained = s.drain(0usize, 5usize)
        match drained.next() {
            present(c) => { if c != 'h' { return 62 } },
            none => { return 63 }
        }
        if drained.as_str() != "ello" { return 64 }
    }
    if s.as_text() != "he" { return 65 }
    s.make_ascii_uppercase()
    if s.as_text() != "HE" { return 66 }
    s.make_ascii_lowercase()
    if s.as_text() != "he" { return 67 }
    0
}

fn checks_comparison_and_formatting(): i32 {
    let a = String("apple")
    let b = String("banana")
    if !(a < b) || b < a { return 70 }
    if a.cmp(b) != Ordering.Less { return 71 }
    if String("x") == String("y") { return 72 }
    var target = String("")
    match capture target.write_str("[") {
        success(_) => {},
        failure(_) => { return 73 }
    }
    match capture fmt.write(mut target, a) {
        success(_) => {},
        failure(_) => { return 74 }
    }
    if target.as_text() != "[apple" { return 79 }
    match capture fmt.write(mut target, 42) {
        success(_) => {},
        failure(_) => { return 75 }
    }
    if target.as_text() != "[apple42" { return 76 }
    let text: read Text = a.as_text()
    if text.len() != 5usize { return 77 }
    if a.len() != 5usize { return 78 }
    0
}

fn main(): i32 {
    let first = checks_construction()
    if first != 0 { return first }
    let second = checks_validated_conversion()
    if second != 0 { return second }
    let third = checks_views_and_bytes()
    if third != 0 { return third }
    let fourth = checks_mutation()
    if fourth != 0 { return fourth }
    let fifth = checks_ranges()
    if fifth != 0 { return fifth }
    checks_comparison_and_formatting()
}
