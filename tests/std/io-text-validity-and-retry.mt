import alloc.string
import alloc.vec
import std.io.{BufRead, Error, ErrorKind, Reader, Writer}

type InterruptedReader { calls: usize }
extend InterruptedReader implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        self.calls += 1usize
        if self.calls == 1usize { throw std.io.from_kind(ErrorKind.Interrupted) }
        if self.calls > 2usize || bytes.is_empty() { return 0usize }
        bytes[0usize] = 120u8
        1usize
    }
}

type PanickingReader { calls: usize }
extend PanickingReader implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        self.calls += 1usize
        if self.calls > 1usize { panic("reader callback") }
        bytes[0usize] = 0xffu8
        1usize
    }
}

type InterruptedWriter { calls: usize; bytes: alloc.vec.List<u8> }
extend InterruptedWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.calls += 1usize
        if self.calls == 1usize { throw std.io.from_kind(ErrorKind.Interrupted) }
        self.bytes.extend_from_slice(bytes)
        bytes.len()
    }
    mut fn flush(): Unit throws Error {}
}

fn run(): i32 throws Error {
    var text = string.from_text("ok")
    let invalid = [0x80u8]
    var reader = std.io.slice_reader(invalid)
    match take capture reader.read_to_string(mut text) {
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidData) { return 1 }
        },
        success(_) => { return 2 }
    }
    if text.as_text() != "ok" { return 3 }
    var lines = std.io.Cursor.new([0x80u8, 10u8])
    match take capture lines.read_line(mut text) {
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidData) { return 4 }
        },
        success(_) => { return 5 }
    }
    if text.as_text() != "ok" { return 6 }
    var bomb = PanickingReader(0usize)
    match take std.panic.catch_panic(fn(): Unit {
        let _ = capture bomb.read_to_string(mut text)
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 7 }
    }
    if text.as_text() != "ok" { return 8 }
    var lending = std.io.buf_reader_with_capacity(1usize, PanickingReader(0usize))
    match take std.panic.catch_panic(fn(): Unit {
        let _ = capture lending.read_line_into(mut text)
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 16 }
    }
    if !text.is_empty() { return 17 }
    var exact = InterruptedReader(0usize)
    var one = [0u8]
    try exact.read_exact(one)
    if one[0usize] != 120u8 { return 9 }
    var end = InterruptedReader(0usize)
    var bytes = vec.new<u8>()
    if try end.read_to_end(mut bytes) != 1usize { return 10 }
    var writer = InterruptedWriter(0usize, vec.new<u8>())
    try writer.write_all("x".as_bytes())
    if writer.bytes.as_slice() != "x".as_bytes() { return 11 }
    var zero = std.io.buf_reader_with_capacity(0usize, std.io.slice_reader("x".as_bytes()))
    try zero.read_exact(one)
    if one[0usize] != 120u8 { return 12 }
    var delimiter = std.io.buf_reader_with_capacity(1usize, InterruptedReader(0usize))
    var collected = vec.new<u8>()
    if try delimiter.read_until(120u8, mut collected) != 1usize { return 13 }
    var skipped = std.io.buf_reader_with_capacity(1usize, InterruptedReader(0usize))
    if try skipped.skip_until(120u8) != 1usize { return 14 }
    var source = InterruptedReader(0usize)
    var target = InterruptedWriter(0usize, vec.new<u8>())
    if try std.io.`copy`(mut source, mut target) != 1u64 { return 15 }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
