import std.io.{BufRead, BufferedReader, Cursor, Error, ErrorKind, Reader, Seek, SeekFrom}

fn run(): i32 throws Error {
    var reader = BufferedReader.with_capacity(
        4usize, Cursor.new([97u8, 98u8, 99u8, 100u8, 101u8, 102u8])
    )
    assert(reader.capacity() >= 4usize, "requested read-ahead capacity")
    assert(reader.buffer().len() == 0usize && reader.get_ref().position() == 0u64,
        "construction performs no source reads")
    let first = try reader.fill_buf()
    assert(first.len() >= 2usize && first[0usize] == 97u8, "initial refill")
    let buffered = reader.buffer().len()
    let physical = reader.get_ref().position()
    assert(physical == buffered as u64, "inner position includes read-ahead")
    assert(try reader.fill_buf().len() == buffered &&
        reader.get_ref().position() == physical, "reuse the current buffer")
    reader.consume(1usize)
    assert(reader.buffer().len() == buffered - 1usize &&
        reader.buffer()[0usize] == 98u8, "consume only advances the buffer")
    reader.get_mut().set_position(5u64)
    assert(reader.get_ref().position() == 5u64 &&
        reader.buffer()[0usize] == 98u8, "mutable inner access does not discard buffered bytes")
    var inner = reader.into_inner()
    var byte = [0u8; 1]
    assert(try inner.read_some(mut byte) == 1usize && byte[0usize] == 102u8,
        "into_inner transfers the physical source and discards read-ahead")

    var seekable = BufferedReader.with_capacity(
        4usize, Cursor.new([97u8, 98u8, 99u8, 100u8, 101u8, 102u8])
    )
    let available = try seekable.fill_buf()
    assert(available[0usize] == 97u8, "seek refill")
    seekable.consume(1usize)
    try seekable.seek_relative(1i64)
    assert(try seekable.read_some(mut byte) == 1usize && byte[0usize] == 99u8,
        "relative seek starts at the logical position")
    match take capture seekable.seek(SeekFrom.Current(-99i64)) {
        success(_) => { return 1 },
        failure(error) => {
            assert(error.kind().is(ErrorKind.InvalidInput), "negative logical seek rejects")
        }
    }
    assert(try seekable.read_some(mut byte) == 1usize && byte[0usize] == 100u8,
        "failed seek preserves unread buffered bytes")

    var empty = BufferedReader.new(Cursor.new([0u8; 0]))
    assert(empty.buffer().len() == 0usize && empty.get_ref().position() == 0u64,
        "default construction is lazy")
    assert(try empty.fill_buf().len() == 0usize && empty.buffer().len() == 0usize,
        "EOF exposes no buffered bytes")
    var minimal = BufferedReader.with_capacity(0usize, Cursor.new([9u8; 1]))
    assert(try minimal.read_some(mut byte) == 1usize && byte[0usize] == 9u8,
        "zero requested capacity preserves readable input")
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
