// A byte Deque is a FIFO pipe: write_all appends, reads and consume pop the front.
import std.io.{Reader, Writer, BufRead, Error}
import alloc.vec
import alloc.vec_deque

fn run(): i32 throws Error {
    var pipe = vec_deque.new<u8>()
    // Wrap the ring so the readable bytes span two slices.
    pipe.push_back(0u8)
    pipe.push_back(0u8)
    let _a = pipe.pop_front()
    let _b = pipe.pop_front()
    let text = [104u8, 101u8, 108u8, 108u8, 111u8, 10u8, 104u8, 105u8]
    try pipe.write_all(text)
    if pipe.len() != 8usize { return 1 }

    let head = try pipe.fill_buf()
    if head.len() == 0usize || head[0usize] != 104u8 { return 2 }
    pipe.consume(2usize)
    if pipe.len() != 6usize { return 3 }

    var line = alloc.vec.new<u8>()
    let n = try pipe.read_until(10u8, line)
    if n != 4usize || line.len() != 4usize { return 4 }

    var two = [0u8; 2]
    try pipe.read_exact(two)
    if two[0usize] != 104u8 || two[1usize] != 105u8 { return 5 }
    if !pipe.is_empty() { return 6 }
    if (try pipe.read_some(two)) != 0usize { return 7 }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 100 }
}
