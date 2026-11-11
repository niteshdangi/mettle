import alloc.vec
import alloc.vec.List
import std.io.{Error, ErrorKind, Writer}

type PartialWriter { bytes: List<u8>; calls: usize }
extend PartialWriter implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.calls += 1usize
        if self.calls == 2usize { throw std.io.from_kind(ErrorKind.Other) }
        let count = if self.calls == 1usize { 1usize } else { bytes.len() }
        self.bytes.extend_from_slice(bytes.split_at(count).0)
        count
    }
    mut fn flush(): Unit throws Error {}
}

type PanicWriter<region r> { bytes: mut List<u8> from r; calls: usize }
extend<region r> PanicWriter<region r> implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.calls += 1usize
        if self.calls == 1usize {
            let first = bytes[0usize]
            self.bytes.push(first)
            panic("writer callback")
        }
        self.bytes.extend_from_slice(bytes)
        bytes.len()
    }
    mut fn flush(): Unit throws Error {}
}

fn run(): i32 throws Error {
    var writer = std.io.buf_writer_with_capacity(8usize, PartialWriter(vec.new<u8>(), 0usize))
    try writer.write_all("abc".as_bytes())
    match take capture writer.flush() {
        failure(_) => {},
        success(_) => { return 1 }
    }
    if writer.buffer() != "bc".as_bytes() { return 2 }
    try writer.flush()
    if writer.get_ref().bytes.as_slice() != "abc".as_bytes() { return 3 }
    var observed = vec.new<u8>()
    match take std.panic.catch_panic(fn(): Unit {
        var bomb = std.io.buf_writer_with_capacity(8usize, PanicWriter(mut observed, 0usize))
        let _ = capture bomb.write_all("abc".as_bytes())
        let _ = capture bomb.flush()
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 4 }
    }
    if observed.as_slice() != "a".as_bytes() { return 5 }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
