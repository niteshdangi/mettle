import std.io.{Error, Writer}

type Bomb { calls: usize }
extend Bomb implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.calls += 1usize
        panic("unknown write progress")
        0usize
    }
    mut fn flush(): Unit throws Error {}
}

fn main(): i32 {
    var untouched = std.io.buf_writer_with_capacity(8usize, Bomb(0usize))
    let _ = capture untouched.write_all("abc".as_bytes())
    let clean = untouched.into_parts()
    if clean.0.calls != 0usize { return 5 }
    match take clean.1 {
        success(bytes) => { if bytes.as_slice() != "abc".as_bytes() { return 6 } },
        failure(_) => { return 7 }
    }
    var writer = std.io.buf_writer_with_capacity(8usize, Bomb(0usize))
    let _ = capture writer.write_all("abc".as_bytes())
    match take std.panic.catch_panic(fn(): Unit { let _ = capture writer.flush() }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 1 }
    }
    let parts = writer.into_parts()
    if parts.0.calls != 1usize { return 2 }
    match take parts.1 {
        failure(error) => {
            let bytes = error.into_inner()
            if bytes.as_slice() != "abc".as_bytes() { return 3 }
        },
        success(_) => { return 4 }
    }
    0
}
