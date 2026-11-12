import alloc.vec
import std.io.{BufRead, BufferedReader, BufferedWriter, Cursor, Error, ErrorKind, Reader, Seek, SeekFrom, Writer}

fn first_byte<R: BufRead>(mut reader: R): u8 throws Error {
    var byte = [0u8]
    try reader.read_exact(mut byte)
    byte[0usize]
}

type TrackedReader { inner: Cursor<[u8; 6]>; seeks: usize }
extend TrackedReader implements Reader {
    mut fn read_some(mut bytes: [u8]): usize throws Error {
        try self.inner.read_some(bytes)
    }
}
extend TrackedReader implements Seek {
    mut fn seek(position: SeekFrom): u64 throws Error {
        self.seeks += 1usize
        try self.inner.seek(position)
    }
    mut fn stream_position(): u64 throws Error { self.inner.position() }
}

type FlushFailure { bytes: alloc.vec.List<u8> }
extend FlushFailure implements Writer {
    mut fn write_some(read bytes: [u8]): usize throws Error {
        self.bytes.extend_from_slice(bytes)
        bytes.len()
    }
    mut fn flush(): Unit throws Error { throw std.io.from_kind(ErrorKind.BrokenPipe) }
}

fn run(): i32 throws Error {
    var buffered = Cursor.new([120u8])
    assert(try first_byte(mut buffered) == 120u8, "buffered input is a byte reader")
    var reader = BufferedReader.with_capacity(4usize,
        TrackedReader(Cursor.new([97u8, 98u8, 99u8, 100u8, 101u8, 102u8]), 0usize))
    var byte = [0u8]
    assert(try reader.read_some(mut byte) == 1usize && byte[0usize] == 97u8, "initial read")
    assert(try reader.stream_position() == 1u64, "position excludes unread bytes")
    assert(reader.buffer() == "bcd".as_bytes(), "position preserves read-ahead")
    try reader.seek_relative(2i64)
    assert(reader.buffer() == "d".as_bytes(), "forward seek stays in buffer")
    try reader.seek_relative(-3i64)
    assert(reader.buffer() == "abcd".as_bytes(), "backward seek reuses consumed bytes")
    assert(reader.get_ref().seeks == 0usize, "in-buffer seeks do not touch the source")
    try reader.seek_relative(5i64)
    assert(reader.get_ref().seeks == 1usize && reader.buffer().is_empty(), "outside seek delegates")
    assert(try reader.read_some(mut byte) == 1usize && byte[0usize] == 102u8, "delegated position")
    match take capture reader.seek_relative(-9223372036854775807i64 - 1i64) {
        failure(error) => { assert(error.kind().is(ErrorKind.InvalidInput), "negative position") },
        success(_) => { return 1 }
    }
    assert(try reader.stream_position() == 6u64, "failed seek preserves position")

    var writer = BufferedWriter.with_capacity(8usize, FlushFailure(vec.new<u8>()))
    try writer.write_all("saved".as_bytes())
    let inner = match take capture writer.into_inner() {
        success(inner) => inner,
        failure(_) => { return 2 }
    }
    assert(inner.bytes.as_slice() == "saved".as_bytes(), "into_inner drains without inner flush")

    var explicit = BufferedWriter.with_capacity(8usize, FlushFailure(vec.new<u8>()))
    try explicit.write_all("kept".as_bytes())
    match take capture explicit.flush() {
        failure(error) => { assert(error.kind().is(ErrorKind.BrokenPipe), "explicit flush reaches inner") },
        success(_) => { return 3 }
    }
    assert(explicit.buffer().is_empty() &&
        explicit.get_ref().bytes.as_slice() == "kept".as_bytes(), "flush failure does not duplicate bytes")

    var seek_writer = BufferedWriter.with_capacity(8usize, Cursor.new([0u8; 4]))
    try seek_writer.write_all("abc".as_bytes())
    assert(try seek_writer.seek(SeekFrom.Start(1u64)) == 1u64, "writer seeks after draining")
    assert(seek_writer.buffer().is_empty() &&
        seek_writer.get_ref().get_ref()[2usize] == 99u8, "seek preserves prior output")
    try seek_writer.write_all("Z".as_bytes())
    let result = match take capture seek_writer.into_inner() {
        success(inner) => inner,
        failure(_) => { return 4 }
    }
    assert(result.position() == 2u64 && result.get_ref()[0usize] == 97u8 &&
        result.get_ref()[1usize] == 90u8 && result.get_ref()[2usize] == 99u8,
        "seeked writes replace only their target bytes")
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
