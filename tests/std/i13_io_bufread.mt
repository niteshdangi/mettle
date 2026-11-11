import alloc.boxed
import core.fmt
import std.io.{BufRead, Cursor, Error, Lines, Reader, Writer}

fn require_lines_markers<B: BufRead + Transferable + Shareable>(read value: Lines<B>) {}
fn require_debug<T: fmt.Debug>(read value: T): Unit {}

fn run(): i32 throws Error {
    let marked_lines = Cursor.new([97u8; 1]).lines()
    require_lines_markers(read marked_lines)
    require_debug(read marked_lines)

    let source = "alpha\r\nbeta\nlast".as_bytes()
    var lines = std.io.buf_reader(std.io.slice_reader(source)).lines()
    match take lines.next() {
        present(success(line)) => {
            if line.as_bytes().len() != 5usize || line.as_bytes()[0usize] != 97u8 {
                return 1
            }
        },
        _ => { return 2 }
    }
    match take lines.next() {
        present(success(line)) => {
            if line.as_bytes().len() != 4usize || line.as_bytes()[0usize] != 98u8 {
                return 3
            }
        },
        _ => { return 4 }
    }
    match take lines.next() {
        present(success(line)) => {
            if line.as_bytes().len() != 4usize || line.as_bytes()[3usize] != 116u8 {
                return 5
            }
        },
        _ => { return 6 }
    }
    match take lines.next() {
        none => {},
        _ => { return 7 }
    }

    var reader = std.io.buf_reader(std.io.slice_reader("one,two,".as_bytes()))
    var parts = reader.split(44u8)
    match take parts.next() {
        present(success(part)) => {
            if part.len() != 3usize || part[0usize] != 111u8 { return 8 }
        },
        _ => { return 9 }
    }
    match take parts.next() {
        present(success(part)) => {
            if part.len() != 3usize || part[0usize] != 116u8 { return 10 }
        },
        _ => { return 11 }
    }
    match take parts.next() {
        none => {},
        _ => { return 12 }
    }

    var read_until = std.io.buf_reader(std.io.slice_reader("skip|keep".as_bytes()))
    if try read_until.skip_until(124u8) != 5usize { return 13 }
    var rest = alloc.vec.new<u8>()
    if try read_until.read_until(124u8, mut rest) != 4usize ||
        rest.len() != 4usize || rest[0usize] != 107u8 {
        return 14
    }

    var boxed_reader = boxed.new(std.io.buf_reader(
        std.io.slice_reader("boxed".as_bytes())
    ))
    let boxed_slice = try boxed_reader.fill_buf()
    if boxed_slice.len() != 5usize || boxed_slice[0usize] != 98u8 { return 15 }
    boxed_reader.consume(2usize)
    if try boxed_reader.skip_until(100u8) != 3usize { return 16 }

    var deque = alloc.vec_deque.with_capacity<u8>(4usize)
    deque.push_back(97u8)
    deque.push_back(98u8)
    deque.push_back(99u8)
    deque.push_back(100u8)
    deque.consume(2usize)
    deque.push_back(101u8)
    deque.push_back(102u8)
    let first = try deque.fill_buf()
    if first.len() != 2usize || first[0usize] != 99u8 || first[1usize] != 100u8 {
        return 17
    }
    deque.consume(2usize)
    let second = try deque.fill_buf()
    if second.len() != 2usize || second[0usize] != 101u8 || second[1usize] != 102u8 {
        return 18
    }
    var bytes = [0u8; 3]
    if try deque.read_some(mut bytes) != 2usize ||
        bytes[0usize] != 101u8 || bytes[1usize] != 102u8 { return 19 }
    if try deque.read_some(mut bytes) != 0usize { return 20 }
    if try deque.write_some("gh".as_bytes()) != 2usize { return 21 }
    if try deque.read_some(mut bytes) != 2usize ||
        bytes[0usize] != 103u8 || bytes[1usize] != 104u8 { return 22 }
    try deque.flush()
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
