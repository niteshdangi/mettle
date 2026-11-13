import alloc.vec
import std.io
import std.io.{Error, Reader, Writer}

fn read_pair<R: Reader>(mut reader: R): u8 throws Error {
    var byte = [0u8; 1]
    let _ = try reader.read_some(byte)
    byte[0usize]
}

fn put<W: Writer>(mut writer: W, byte: u8): Unit throws Error {
    try writer.write_all([byte])
}

fn run(): i32 throws Error {
    let data = [1u8, 2u8]
    var first = io.slice_reader(data)
    if try read_pair(first.by_ref()) != 1u8 { return 1 }
    let tail = [7u8]
    var chained = first.chain(io.slice_reader(tail))
    var all = [0u8; 4]
    let count = try chained.read_some(all)
    if count != 1usize || all[0usize] != 2u8 { return 2 }
    if try chained.read_some(all) != 1usize || all[0usize] != 7u8 { return 3 }

    var buffered = io.buf_writer(vec.new<u8>())
    if buffered.capacity() != 8192usize { return 4 }
    try put(buffered.by_ref(), 9u8)
    buffered.get_mut().push(5u8)
    if buffered.buffered() != 1usize || buffered.get_ref().len() != 1usize { return 5 }

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
