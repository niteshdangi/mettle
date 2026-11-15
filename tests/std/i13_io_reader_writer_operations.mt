import core.clone.Clone
import alloc.vec
import std.io
import std.io.{BufRead, Error, Reader, Seek, Writer}

fn read_pair<R: Reader>(mut reader: R): u8 throws Error {
    var byte = [0u8; 1]
    let _ = try reader.read_some(byte)
    byte[0usize]
}

fn put<W: Writer>(mut writer: W, byte: u8): Unit throws Error {
    try writer.write_all([byte])
}

fn peek<B: BufRead>(mut reader: B): u8 throws Error {
    let available = try reader.fill_buf()
    available[0usize]
}

fn available<B: BufRead>(mut reader: B): usize throws Error {
    let bytes = try reader.fill_buf()
    bytes.len()
}

fn position<region r, S: Seek>(mut stream: mut S from r): u64 throws Error {
    try stream.stream_position()
}

fn run(): i32 throws Error {
    var direct_bytes = [0u8; 3]
    {
        var direct = mut direct_bytes[..]
        if try direct.write_some([1u8, 2u8]) != 2usize { return 20 }
        if try direct.write_some([3u8, 4u8]) != 1usize { return 21 }
        if try direct.write_some([5u8]) != 0usize { return 22 }
        try direct.flush()
    }
    if direct_bytes[0usize] != 1u8 || direct_bytes[2usize] != 3u8 { return 23 }

    var split_bytes = [1u8, 2u8, 3u8, 4u8, 5u8, 6u8]
    {
        var view = io.IoSliceMut.new(mut split_bytes[..])
        let first = view.split_off_first().or_panic()
        let last = view.split_off_last().or_panic()
        let prefix = view.split_off(core.iter.range_to(1usize)).or_panic()
        let first_mut = view.split_off_first_mut().or_panic()
        let last_mut = view.split_off_last_mut().or_panic()
        let middle = view.split_off_mut(core.iter.range_to(1usize)).or_panic()
        if *first != 1u8 || *last != 6u8 || prefix[0usize] != 2u8 { return 24 }
        *first_mut = 10u8
        *last_mut = 11u8
        middle[0usize] = 12u8
        if view.split_off_first_mut().is_present() { return 25 }
    }
    if split_bytes[2usize] != 10u8 || split_bytes[3usize] != 12u8 ||
        split_bytes[4usize] != 11u8 { return 26 }

    let data = [1u8, 2u8]
    var first = io.slice_reader(data)
    if try read_pair(first.by_ref()) != 1u8 { return 1 }
    let tail = [7u8]
    var chained = first.chain(io.slice_reader(tail))
    var all = [0u8; 4]
    let count = try chained.read_some(all)
    if count != 1usize || all[0usize] != 2u8 { return 2 }
    if try chained.read_some(all) != 1usize || all[0usize] != 7u8 { return 3 }

    let lines_data = [97u8, 10u8, 98u8]
    var slice_lines = io.slice_reader(lines_data)
    if try peek(slice_lines.by_ref()) != 97u8 { return 6 }
    slice_lines.consume(2usize)
    if try available(slice_lines.by_ref()) != 1usize { return 7 }
    slice_lines.consume(9usize)
    if try available(slice_lines.by_ref()) != 0usize { return 8 }

    var window = [0u8; 4]
    {
        var target = io.Cursor.new(mut window[..])
        try target.write_all([5u8, 6u8, 7u8])
        if target.position() != 3u64 { return 9 }
        if try position(mut target) != 3u64 { return 13 }
    }
    if window[0usize] != 5u8 || window[2usize] != 7u8 || window[3usize] != 0u8 { return 10 }

    var buffered = io.buf_writer(vec.new<u8>())
    if buffered.capacity() != 8192usize { return 4 }
    try put(buffered.by_ref(), 9u8)
    buffered.get_mut().push(5u8)
    if buffered.buffered() != 1usize || buffered.get_ref().len() != 1usize { return 5 }

    let (pipe_reader, pipe_writer) = try io.pipe()
    {
        var writer = read pipe_writer
        try writer.write_all("borrow".as_bytes())
    }
    {
        var reader = read pipe_reader
        var borrowed = [0u8; 6]
        try reader.read_exact(mut borrowed)
        if borrowed[0usize] != 98u8 || borrowed[5usize] != 119u8 { return 12 }
    }

    var sink = io.sink()
    var copied_sink = sink
    var cloned_sink = sink.clone()
    let discarded = "discard".as_bytes()
    if try sink.write_some(discarded) != discarded.len() { return 11 }
    try copied_sink.write_all(discarded)
    try cloned_sink.flush()

    let lock = io.stdin().lock()
    core.mem.drop(take lock)
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
