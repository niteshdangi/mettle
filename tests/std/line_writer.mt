import alloc.vec
import std.io
import std.io.Writer

fn run(): i32 throws io.Error {
    var writer = io.LineWriter.new(vec.new<u8>())
    try writer.write_some("first".as_bytes())
    if writer.get_ref().len() != 0usize { return 1 }
    try writer.write_some(" line\nsecond".as_bytes())
    if writer.get_ref().as_slice() != "first line\n".as_bytes() { return 2 }
    try writer.flush()
    if writer.get_ref().as_slice() != "first line\nsecond".as_bytes() { return 3 }
    try writer.write_some(" tail".as_bytes())
    let inner = match take capture writer.into_inner() {
        success(inner) => inner,
        failure(error) => throw error.into_error()
    }
    if inner.as_slice() != "first line\nsecond tail".as_bytes() { return 4 }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
