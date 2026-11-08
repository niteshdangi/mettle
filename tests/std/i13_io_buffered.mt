// Buffered reading keeps byte order across fill_buf, consume and read_line;
// buffered writing holds small writes until flush and passes large ones through.
import alloc.vec.List
import std.io.{Error, Reader, Writer}

fn run(): i32 throws Error {
    // Reading lines through a small buffer.
    let source = "alpha\nbeta\ngamma".as_bytes()
    var reader = std.io.buf_reader_with_capacity(4usize, std.io.slice_reader(source))
    var line = alloc.vec.new<u8>()
    let first = try reader.read_line(mut line)
    if first != 6usize || line.len() != 6usize { return 1 }
    if line[0usize] != 97u8 { return 2 }

    line.clear()
    let peeked = try reader.fill_buf()
    if peeked.len() == 0usize || peeked[0usize] != 98u8 { return 3 }
    reader.consume(1usize)
    let second = try reader.read_line(mut line)
    if second != 4usize || line[0usize] != 101u8 { return 4 }

    line.clear()
    let last = try reader.read_line(mut line)
    if last != 5usize || line[4usize] != 97u8 { return 5 }
    line.clear()
    let eof = try reader.read_line(mut line)
    if eof != 0usize { return 6 }

    // Small writes are held until flush; a write larger than the buffer goes through.
    var writer = std.io.buf_writer_with_capacity(8usize, alloc.vec.new<u8>())
    try writer.write_all("abc".as_bytes())
    if writer.buffered() != 3usize || writer.get_ref().len() != 0usize { return 7 }
    try writer.flush()
    if writer.buffered() != 0usize || writer.get_ref().len() != 3usize { return 8 }
    if writer.get_ref()[0usize] != 97u8 { return 9 }
    try writer.write_all("0123456789abcdefXYZ".as_bytes())
    try writer.flush()
    if writer.get_ref().len() != 22usize { return 10 }
    if writer.get_ref()[21usize] != 90u8 { return 11 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
