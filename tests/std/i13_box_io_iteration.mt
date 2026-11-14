import alloc.boxed
import alloc.boxed.Heap
import alloc.vec
import core.iter.OwnedIterable
import std.io.{BufRead, Cursor, Error, Reader, Seek, SeekFrom, Writer}

fn read_one<R: Reader>(mut reader: R): u8 throws Error {
    var byte = [0u8; 1]
    let _ = try reader.read_some(byte)
    byte[0usize]
}
fn rewind<S: Seek>(mut stream: S): u64 throws Error { try stream.seek(SeekFrom.Start(1u64)) }
fn peek<B: BufRead>(mut reader: B): u8 throws Error {
    let available = try reader.fill_buf()
    available[0usize]
}

fn run(): i32 throws Error {
    let owned_slice = Heap<[i32]>.(core.convert.From<[i32; 3]>).from([1, 2, 3])
    var total = 0
    for value in read owned_slice { total += *value }
    var mutable = Heap<[i32]>.(core.convert.From<[i32; 3]>).from([1, 2, 3])
    for value in mut mutable { *value += 1 }
    for value in Heap<[i32]>.(OwnedIterable).into_iter(mutable) { total += value }
    if total != 6 + 9 { return 1 }

    var fixed = boxed.new([4, 5])
    for value in mut fixed { *value += 1 }
    if fixed.get()[0usize] != 5 { return 7 }
    for value in mut fixed { *value -= 1 }
    var sum = 0
    for value in read fixed { sum += *value }
    for value in Heap<[i32; 2]>.(OwnedIterable).into_iter(fixed) { sum += value }
    if sum != 18 { return 2 }

    if try read_one(boxed.new(Cursor.new([7u8, 8u8]))) != 7u8 { return 3 }
    if try peek(boxed.new(Cursor.new([6u8, 9u8]))) != 6u8 { return 4 }
    if try rewind(boxed.new(Cursor.new([1u8, 2u8]))) != 1u64 { return 5 }
    var sink = boxed.new(vec.new<u8>())
    try sink.write_all([3u8])
    if sink.get().len() != 1usize || sink.get().as_slice()[0usize] != 3u8 { return 6 }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
