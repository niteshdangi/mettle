import std.io
import std.io.{Error, Reader, Writer}

fn emit<W: Writer>(take sink: W): usize throws Error {
    var owned = sink
    var empty = [0u8; 0]
    try owned.write_some(empty)
}

fn drain<R: Reader>(take source: R): usize throws Error {
    var owned = source
    var byte = [0u8; 1]
    try owned.read_some(byte)
}

fn run(): i32 throws Error {
    let out = io.stdout()
    let err = io.stderr()
    let input = io.stdin()
    if try emit(read out) != 0usize || try emit(read err) != 0usize { return 1 }
    if try drain(read input) > 1usize { return 2 }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
