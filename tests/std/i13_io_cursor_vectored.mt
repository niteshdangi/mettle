import core.borrow.AsMut
import core.clone.Clone
import core.default.Default
import core.fmt
import alloc.string.String
import std.io.{BufRead, Cursor, Error, IoSlice, IoSliceMut, Reader, Seek, SeekFrom, Writer}

fn require_cursor_markers<T: Transferable + Shareable>(read value: T): Unit {}

fn render_debug<T: fmt.Debug>(read value: T): String throws Error {
    var output = alloc.string.new()
    {
        var formatter = fmt.formatter(mut output, fmt.spec())
        match capture T.(fmt.Debug).fmt(value, mut formatter) {
            success(_) => {},
            failure(_) => { throw std.io.from_kind(std.io.ErrorKind.Other) }
        }
    }
    output
}

fn run(): i32 throws Error {
    var cursor = Cursor.new([97u8, 98u8, 99u8, 100u8, 101u8, 102u8])
    var first = [0u8; 2]
    if try cursor.read_some(first) != 2usize ||
        first[0usize] != 97u8 || first[1usize] != 98u8 ||
        cursor.position() != 2u64 {
        return 1
    }
    let remaining = try cursor.fill_buf()
    if remaining.len() != 4usize || remaining[0usize] != 99u8 { return 2 }
    cursor.consume(2usize)
    if try cursor.seek(SeekFrom.Current(-1i64)) != 3u64 { return 3 }
    if try cursor.seek(SeekFrom.End(-1i64)) != 5u64 { return 4 }
    cursor.set_position(1u64)
    if cursor.position() != 1u64 { return 16 }
    if try cursor.seek(SeekFrom.Start(0xffffffffffffffffu64)) != 0xffffffffffffffffu64 {
        return 5
    }
    let overflow = capture cursor.seek(SeekFrom.Current(1i64))
    match take overflow {
        success(_) => { return 6 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.InvalidInput) { return 7 }
        }
    }
    if cursor.position() != 0xffffffffffffffffu64 { return 21 }
    var past_end = [0u8; 1]
    if try cursor.read_some(mut past_end) != 0usize ||
        (try cursor.fill_buf()).len() != 0usize { return 22 }
    if cursor.position() != 0xffffffffffffffffu64 { return 23 }
    if try cursor.seek(SeekFrom.Current(-9223372036854775807i64 - 1i64)) !=
        9223372036854775807u64 { return 43 }
    cursor.set_position(0u64)
    match take capture cursor.seek(SeekFrom.Current(-1i64)) {
        success(_) => { return 24 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.InvalidInput) { return 25 }
        }
    }
    if cursor.position() != 0u64 { return 26 }
    match take capture cursor.seek(SeekFrom.End(-9223372036854775807i64 - 1i64)) {
        success(_) => { return 27 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.InvalidInput) { return 28 }
        }
    }
    if cursor.position() != 0u64 { return 29 }
    cursor.set_position(5u64)
    var too_long = [0u8; 2]
    match take capture cursor.read_exact(mut too_long) {
        success(_) => { return 30 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.UnexpectedEof) { return 31 }
        }
    }
    if cursor.position() != 6u64 || too_long[0usize] != 102u8 { return 32 }

    var vectored_reader = Cursor.new([119u8, 120u8, 121u8, 122u8])
    var empty = [0u8; 0]
    var second = [0u8; 2]
    var third = [0u8; 2]
    var read_buffers = [
        IoSliceMut.new(mut empty),
        IoSliceMut.new(mut second),
        IoSliceMut.new(mut third)
    ]
    if try vectored_reader.read_vectored(mut read_buffers) != 2usize ||
        second[0usize] != 119u8 || second[1usize] != 120u8 ||
        third[0usize] != 0u8 || vectored_reader.position() != 2u64 {
        return 8
    }

    var writer = Cursor.new([0u8; 4])
    let write_buffers = [IoSlice.new("".as_bytes()), IoSlice.new("abc".as_bytes())]
    if try writer.write_vectored(write_buffers) != 3usize { return 9 }
    if try writer.write_some("de".as_bytes()) != 1usize { return 10 }
    if writer.get_ref()[0usize] != 97u8 || writer.get_ref()[3usize] != 100u8 {
        return 11
    }
    if try writer.seek(SeekFrom.Start(0u64)) != 0u64 { return 12 }
    try writer.write_all("xy".as_bytes())
    if writer.get_ref()[0usize] != 120u8 || writer.get_ref()[1usize] != 121u8 {
        return 13
    }
    writer.set_position(3u64)
    match take capture writer.write_all("zz".as_bytes()) {
        success(_) => { return 33 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.WriteZero) { return 34 }
        }
    }
    if writer.position() != 4u64 || writer.get_ref()[3usize] != 122u8 { return 35 }
    if try writer.write_some("".as_bytes()) != 0usize || writer.position() != 4u64 {
        return 41
    }
    writer.set_position(0xffffffffffffffffu64)
    if try writer.write_some("x".as_bytes()) != 0usize ||
        writer.position() != 0xffffffffffffffffu64 { return 36 }
    try writer.flush()
    let cloned = writer.clone()
    if cloned != writer || !(try render_debug(read cloned)).as_text().starts_with("Cursor") {
        return 17
    }
    let default_cursor = Cursor<[u8; 2]>.(Default).default()
    if default_cursor.get_ref()[0usize] != 0u8 ||
        !(try render_debug(read default_cursor)).as_text().starts_with("Cursor") {
        return 18
    }
    require_cursor_markers(read default_cursor)
    var mutable_cursor = Cursor.new([0u8; 2])
    mutable_cursor.get_mut()[0usize] = 77u8
    if mutable_cursor.get_ref()[0usize] != 77u8 { return 20 }

    var external = [0u8; 3]
    let target = [u8; 3].(AsMut<[u8]>).as_mut(mut external)
    var slice_cursor = Cursor.new(target)
    if try slice_cursor.write_some("ok!".as_bytes()) != 3usize { return 14 }
    if slice_cursor.get_ref()[0usize] != 111u8 ||
        slice_cursor.get_ref()[2usize] != 33u8 {
        return 15
    }
    slice_cursor.set_position(2u64)
    match take capture slice_cursor.write_all("xy".as_bytes()) {
        success(_) => { return 37 },
        failure(error) => {
            if !error.kind().is(std.io.ErrorKind.WriteZero) { return 38 }
        }
    }
    if slice_cursor.position() != 3u64 || slice_cursor.get_ref()[2usize] != 120u8 {
        return 39
    }
    if try slice_cursor.write_some("".as_bytes()) != 0usize ||
        slice_cursor.position() != 3u64 { return 42 }
    slice_cursor.set_position(0xffffffffffffffffu64)
    if try slice_cursor.write_some("x".as_bytes()) != 0usize ||
        slice_cursor.position() != 0xffffffffffffffffu64 { return 40 }
    try slice_cursor.flush()
    let inner = slice_cursor.into_inner()
    if inner[0usize] != 111u8 || inner[2usize] != 120u8 { return 19 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
