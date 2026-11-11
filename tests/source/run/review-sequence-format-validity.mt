// profiles: debug release
import core.clone.Clone
import core.fmt
import core.fmt.{Debug, Display, Error, Formatter, Write}
import core.iter.Iterator
import core.text.Text
import std.panic.CatchResult

fn debug_is<T: unsized + Debug>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 128]
    var sink = fmt.buffer_writer(mut buffer)
    var f = fmt.formatter(mut sink, fmt.spec())
    match capture T.(Debug).fmt(value, mut f) {
        success(_) => {},
        failure(_) => { return false }
    }
    let length = sink.len()
    match fmt.written_text(read buffer, length) { present(text) => text == expected, none => false }
}
type Custom {}
extend Custom implements Display {
    fn fmt(mut f: Formatter): Unit throws Error { try f.write_str("custom") }
}
fn emit(message: format fmt.Message, mut sink: [u8]): usize throws Error {
    var writer = fmt.buffer_writer(mut sink)
    try message.write_to(mut writer)
    writer.len()
}
fn main(): i32 {
    var substring = "ababa".split("aba")
    var cloned = substring.clone()
    match cloned.next() { present(part) => assert(part.is_empty(), "substring split clone"), none => panic("missing clone field") }
    assert(debug_is(substring, "Split { rest: \"ababa\", separator: \"aba\", done: false }"), "substring split debug witness")
    assert(debug_is('\0', "'\\0'"), "NUL debug shortcut")
    assert(debug_is("\u{1b}", "\"\\u{1b}\""), "control debug escape")
    assert(debug_is("\u{200d}", "\"\\u{200d}\""), "format-control debug escape")
    assert(debug_is('"', "'\"'") && debug_is("'", "\"'\""), "only active quote escaped")
    var scalar_escape = "\u{301}".escape_debug()
    assert(scalar_escape.next() == present('\\'), "first grapheme extension is escaped")
    var after = "a\u{301}".escape_debug()
    assert(after.next() == present('a') && after.next() == present('\u{301}'), "later combining mark literal")
    var buffer = [0u8; 64]
    var count = 0usize
    match capture emit(f"{Custom()}", mut buffer) { success(n) => { count = n }, failure(_) => panic("format custom") }
    assert(count == 6usize && buffer[0usize] == 99u8, "sealed bridge preserves Display holes")
    match capture emit(f"", mut buffer) { success(n) => assert(n == 0usize, "empty literal bridge"), failure(_) => panic("empty literal") }
    {
        var writer = fmt.buffer_writer(mut buffer)
        var options = fmt.spec()
        options.width = present(3usize)
        options.alternate = true
        var f = fmt.formatter(mut writer, options)
        match capture f.pad_integral(true, "\u{a3}", "1") {
            success(_) => {},
            failure(_) => panic("pad integral")
        }
        assert(writer.len() == 4usize, "one pad scalar plus multibyte prefix and digit")
    }
    assert(buffer[0usize] == 32u8 && buffer[1usize] == 0xc2u8, "right aligned Unicode prefix")
    var before = [42u8; 4]
    let rejected = std.panic.catch_panic(fn(): Unit {
        var writer = fmt.buffer_writer(mut before)
        var f = fmt.formatter(mut writer, fmt.spec())
        let _ = capture fmt.fmt_radix(mut f, 100u64, false, 128u64, false, "")
    })
    match take rejected { CatchResult.Panicked(_) => {}, CatchResult.Returned(_) => panic("invalid radix accepted") }
    assert(before[0usize] == 42u8, "reject radix before output")
    0
}
