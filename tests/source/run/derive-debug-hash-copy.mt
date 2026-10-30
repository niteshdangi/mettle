import core.fmt.{Debug, Error, Write, Formatter, buffer_writer, formatter, spec, written_text}
import core.hash.{Hash, hash_one}
import core.clone.Clone

@derive(Clone, Copy, Debug, Hash)
type Point { x: i32; y: i32 }

@derive(Debug, Hash)
enum Token { Eof, Num(i32), Pair { left: i32, right: i32 } }

@derive(Debug, Clone)
type Boxed<T> { inner: T }

fn render<T: Debug>(value: read T, buffer: mut [u8]): usize throws Error {
    var out = buffer_writer(mut buffer)
    var f = formatter(mut out, spec())
    try value.fmt(mut f)
    out.len()
}

fn run(): i32 throws Error {
    var buffer = [0u8; 64]
    let p = Point(1, 2)
    let dup = p
    let n = try render(read dup, mut buffer)
    match written_text(read buffer, n) {
        present(t) => { if t != "Point { x: 1, y: 2 }" { return 1 } },
        none => { return 2 }
    }
    let m = try render(read Token.Num(7), mut buffer)
    match written_text(read buffer, m) {
        present(t) => { if t != "Num(7)" { return 3 } },
        none => { return 4 }
    }
    if hash_one(read p) != hash_one(read Point(1, 2)) { return 5 }
    if hash_one(read Token.Num(1)) == hash_one(read Token.Eof) { return 6 }
    let b = Boxed(Point(3, 4)).clone()
    let k = try render(read b, mut buffer)
    match written_text(read buffer, k) {
        present(t) => { if t != "Boxed { inner: Point { x: 3, y: 4 } }" { return 7 } },
        none => { return 8 }
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(e) => 99 }
}
