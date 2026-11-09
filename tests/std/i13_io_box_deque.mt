import alloc.boxed
import alloc.collections.Deque
import std.fs.{OpenOptions, SeekFrom}
import std.io.{Error, Reader, Seek, Writer}
import std.path.path_from_text

fn run(): i32 throws Error {
    var deque: Deque<u8> = alloc.vec_deque.with_capacity<u8>(4usize)
    deque.push_back(97u8)
    deque.push_back(98u8)
    deque.push_back(99u8)
    var first = [0u8; 2]
    if try deque.read_some(first) != 2usize ||
        first[0usize] != 97u8 || first[1usize] != 98u8 {
        return 1
    }
    if try deque.write_some("de".as_bytes()) != 2usize ||
        deque.len() != 3usize {
        return 2
    }
    var tail = [0u8; 3]
    if try deque.read_some(tail) != 3usize ||
        tail[0usize] != 99u8 || tail[1usize] != 100u8 ||
        tail[2usize] != 101u8 {
        return 3
    }
    try deque.flush()

    var boxed_deque = boxed.new(alloc.vec_deque.new<u8>())
    if try boxed_deque.write_some("box".as_bytes()) != 3usize { return 4 }
    var boxed_bytes = [0u8; 3]
    if try boxed_deque.read_some(boxed_bytes) != 3usize ||
        boxed_bytes[0usize] != 98u8 || boxed_bytes[2usize] != 120u8 {
        return 5
    }
    try boxed_deque.flush()

    let path = path_from_text("i13-io-box-seek")
    var options = OpenOptions.new()
    options.`read`(true)
    options.write(true)
    options.create(true)
    options.truncate(true)
    var file = try options.open(path)
    var boxed_file = boxed.new(file)
    try boxed_file.write_all("seek".as_bytes())
    if try boxed_file.seek(SeekFrom.Start(0u64)) != 0u64 { return 6 }
    var file_bytes = [0u8; 4]
    try boxed_file.read_exact(file_bytes)
    if file_bytes[0usize] != 115u8 || file_bytes[3usize] != 107u8 {
        return 7
    }
    core.mem.drop(take boxed_file)
    try std.fs.remove_file(path)
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
