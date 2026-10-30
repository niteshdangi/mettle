import core::fmt;
import core::fmt::Write;
import core::fmt::Display;

type Pt { x: i32; y: i32 }
impl Pt implements Display {
    fn fmt<W: fmt::Write>(f: mut fmt::Formatter<W>): Unit throws fmt::Error {
        try f.write_str("(")
        try self.x.fmt(mut f)
        try f.write_str(",")
        try self.y.fmt(mut f)
        try f.write_str(")")
    }
}

type Word {}
impl Word implements Display {
    fn fmt<W: fmt::Write>(f: mut fmt::Formatter<W>): Unit throws fmt::Error { try f.pad("hello") }
}

fn write_text<W: fmt::Write>(sink: mut W, text: read core::text::Text, options: fmt::Spec): Unit throws fmt::Error {
    var f = fmt::formatter(mut sink, options)
    try f.pad(text)
}

fn check<T: Display>(value: read T, options: fmt::Spec, expect: read core::text::Text): bool {
    var storage = [0u8; 64]
    var w = fmt::buffer_writer(mut storage)
    match capture fmt::write_with(mut w, value, options) { success(u) => {}, failure(e) => { return false } }
    let n = w.len()
    match fmt::written_text(read storage, n) { present(t) => t == expect, none => false }
}

fn main(): i32 {
    let s = fmt::spec()
    if !check(42, s, "42") { return 1 }
    if !check(-42i64, s, "-42") { return 2 }
    if !check(-9223372036854775807i64 - 1i64, s, "-9223372036854775808") { return 3 }
    if !check(255u8, s, "255") { return 4 }
    if !check(true, s, "true") { return 5 }
    if !check('é', s, "é") { return 6 }
    if !check(Word(), s, "hello") { return 7 }
    var w5 = fmt::spec()
    w5.width = present(5usize)
    if !check(42, w5, "   42") { return 9 }
    w5.align = fmt::Align::Left
    w5.fill = '*'
    if !check(42, w5, "42***") { return 10 }
    w5.align = fmt::Align::Center
    if !check(7, w5, "**7**") { return 11 }
    var pl = fmt::spec()
    pl.plus = true
    if !check(5, pl, "+5") { return 12 }
    var pr = fmt::spec()
    pr.precision = present(2usize)
    if !check(Word(), pr, "he") { return 13 }
    var padded = [0u8; 8]
    var pw = fmt::buffer_writer(mut padded)
    var width = fmt::spec()
    width.width = present(4usize)
    match capture write_text(mut pw, "ab", width) { success(u) => {}, failure(e) => { return 17 } }
    if pw.len() != 4usize { return 17 }
    // writer failure: 3-byte buffer
    var small = [0u8; 3]
    var sw = fmt::buffer_writer(mut small)
    match capture fmt::write(mut sw, 123456) { success(u) => { return 14 }, failure(e) => {} }
    var cnt = fmt::Counter(0usize)
    match capture fmt::write(mut cnt, 123456) { success(u) => {}, failure(e) => { return 15 } }
    if cnt.bytes != 6usize { return 16 }
    0
}
