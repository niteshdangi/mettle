// expect-error: ownership 8:5 access or storage lifetime conflicts
import std.io.{BufRead, Cursor, Error}

fn check(): Unit throws Error {
    var bytes = [1u8, 2u8]
    var cursor = Cursor.new(mut bytes[..])
    let remaining = try cursor.fill_buf()
    bytes[0usize] = 3u8
    let count = remaining.len()
}

fn main(): i32 { 0 }
