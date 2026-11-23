import alloc.vec
import std.io
import std.io.Writer

type PartialWriter { bytes: vec.List<u8>; calls: usize }
extend PartialWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws io.Error {
        self.calls += 1usize
        if self.calls == 2usize { throw io.from_kind(io.ErrorKind.Other) }
        let count = if self.calls == 1usize { 1usize } else { bytes.len() }
        self.bytes.extend_from_slice(bytes.split_at(count).0)
        count
    }
    mut fn flush(): Unit throws io.Error {}
}

type PanicWriter { bytes: vec.List<u8>; calls: usize }
extend PanicWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws io.Error {
        self.calls += 1usize
        if self.calls == 1usize { panic("line writer retry") }
        self.bytes.extend_from_slice(bytes)
        bytes.len()
    }
    mut fn flush(): Unit throws io.Error {}
}

fn run(): i32 throws io.Error {
    var writer = io.LineWriter.new(vec.new<u8>())
    try writer.write_some("first".as_bytes())
    if writer.get_ref().len() != 0usize { return 1 }
    try writer.write_some(" line\nsecond".as_bytes())
    if writer.get_ref().as_slice() != "first line\n".as_bytes() { return 2 }
    try writer.flush()
    if writer.get_ref().as_slice() != "first line\nsecond".as_bytes() { return 3 }
    try writer.write_some(" tail".as_bytes())
    let inner = match take capture writer.into_inner() {
        success(inner) => inner,
        failure(error) => throw error.into_error()
    }
    if inner.as_slice() != "first line\nsecond tail".as_bytes() { return 4 }
    var partial = io.LineWriter.new(PartialWriter(vec.new<u8>(), 0usize))
    try partial.write_some("abcd".as_bytes())
    match take capture partial.flush() {
        failure(_) => {},
        success(_) => { return 5 }
    }
    try partial.write_some("\nc".as_bytes())
    if partial.get_ref().bytes.as_slice() != "abcd\n".as_bytes() { return 6 }
    try partial.flush()
    if partial.get_ref().bytes.as_slice() != "abcd\nc".as_bytes() { return 6 }
    var retry = io.LineWriter.new(PanicWriter(vec.new<u8>(), 0usize))
    try retry.write_some("prefix".as_bytes())
    match take std.panic.catch_panic(fn(): Unit {
        let _ = capture retry.write_some("\ntail".as_bytes())
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 7 }
    }
    try retry.write_some("!".as_bytes())
    if retry.get_ref().bytes.as_slice() != "prefix\n".as_bytes() { return 8 }
    try retry.flush()
    if retry.get_ref().bytes.as_slice() != "prefix\ntail!".as_bytes() { return 9 }
    var short = io.LineWriter.new(PartialWriter(vec.new<u8>(), 0usize))
    let accepted = try short.write_some("a\nb".as_bytes())
    if accepted != 1usize { return 10 }
    if short.get_ref().bytes.as_slice() != "a".as_bytes() { return 11 }
    try short.write_some("\nb".as_bytes())
    if short.get_ref().bytes.as_slice() != "a\n".as_bytes() { return 12 }
    try short.flush()
    if short.get_ref().bytes.as_slice() != "a\nb".as_bytes() { return 13 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
