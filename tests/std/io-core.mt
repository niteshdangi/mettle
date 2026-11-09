// std.io error kinds, OS error round-trips, slice/buffered readers and writers.
import alloc.vec
import alloc.vec.List
import std.io.{Error, ErrorKind, Reader, Writer, from_kind, from_raw_os_error, with_kind}

copy type Blocked { unused: u8 }
extend Blocked implements Writer {
    mut fn write_some(buf: read [u8]): usize throws Error { 0usize }
    mut fn flush(): Unit throws Error {}
}

fn run(): i32 throws Error {
    let kinds = [
        ErrorKind.NotFound, ErrorKind.PermissionDenied, ErrorKind.ConnectionRefused,
        ErrorKind.ConnectionReset, ErrorKind.ConnectionAborted, ErrorKind.NotConnected,
        ErrorKind.AddrInUse, ErrorKind.AddrNotAvailable, ErrorKind.BrokenPipe,
        ErrorKind.AlreadyExists, ErrorKind.WouldBlock, ErrorKind.InvalidInput,
        ErrorKind.TimedOut, ErrorKind.Interrupted, ErrorKind.OutOfMemory,
        ErrorKind.IsADirectory, ErrorKind.NotADirectory, ErrorKind.DirectoryNotEmpty,
        ErrorKind.Other, ErrorKind.InvalidData, ErrorKind.WriteZero,
        ErrorKind.UnexpectedEof, ErrorKind.Unsupported
    ]
    var i = 0usize
    while i < 23usize {
        var j = 0usize
        while j < 23usize {
            if (i == j) != kinds[i].is(kinds[j]) { return 1 }
            j += 1usize
        }
        if !from_kind(kinds[i]).kind().is(kinds[i]) { return 2 }
        match from_kind(kinds[i]).raw_os_error() {
            present(_) => { return 3 },
            none => {}
        }
        i += 1usize
    }

    let missing = from_raw_os_error(2)
    if !missing.kind().is(ErrorKind.NotFound) || !missing.is_os() { return 4 }
    match missing.raw_os_error() {
        present(code) => { if code != 2 { return 5 } },
        none => { return 5 }
    }
    if !from_raw_os_error(13).kind().is(ErrorKind.PermissionDenied) { return 6 }
    let forced = with_kind(11, ErrorKind.TimedOut)
    if !forced.kind().is(ErrorKind.TimedOut) { return 7 }
    match forced.raw_os_error() {
        present(code) => { if code != 11 { return 8 } },
        none => { return 8 }
    }

    // Reading from a slice: exact fills, end of input, short input.
    let source = "hello world".as_bytes()
    var reader = std.io.slice_reader(source)
    var head = [0u8; 5]
    try reader.read_exact(head)
    if head[0usize] != 104u8 || head[4usize] != 111u8 { return 9 }
    var tail = alloc.vec.new<u8>()
    let moved = try reader.read_to_end(mut tail)
    if moved != 6usize || tail.len() != 6usize { return 10 }
    var empty = [0u8; 1]
    let eof = try reader.read_some(empty)
    if eof != 0usize { return 11 }
    let short = capture reader.read_exact(empty)
    match take short {
        success(_) => { return 12 },
        failure(e) => { if !e.kind().is(ErrorKind.UnexpectedEof) { return 13 } }
    }

    // Writing: list sinks take everything; a sink that accepts nothing is WriteZero.
    var out = alloc.vec.new<u8>()
    try out.write_all("ab".as_bytes())
    try out.write_line(f"{7}")
    if out.len() != 4usize || out[3usize] != 10u8 { return 14 }
    var blocked = Blocked(0u8)
    let stuck = capture blocked.write_all("x".as_bytes())
    match take stuck {
        success(_) => { return 15 },
        failure(e) => { if !e.kind().is(ErrorKind.WriteZero) { return 16 } }
    }

    // Buffered line reads split on LF, keep CR, and return none at end of input.
    var lines = std.io.buf_reader_with_capacity(3usize, std.io.slice_reader("one\r\ntwo\nthree".as_bytes()))
    var raw = alloc.vec.new<u8>()
    let first = try lines.read_bytes_line_into(mut raw)
    match first {
        present(_) => {},
        none => { return 17 }
    }
    if raw.len() != 5usize || raw[3usize] != 13u8 { return 17 }
    let second = try lines.read_bytes_line_into(mut raw)
    match second {
        present(_) => {},
        none => { return 18 }
    }
    if raw.len() != 4usize { return 18 }
    let third = try lines.read_bytes_line_into(mut raw)
    match third {
        present(_) => {},
        none => { return 19 }
    }
    if raw.len() != 5usize { return 19 }
    let done = try lines.read_bytes_line_into(mut raw)
    match done {
        present(_) => { return 20 },
        none => {}
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
