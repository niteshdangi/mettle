import std.io.{Error, Reader, Writer}
import alloc.vec
import alloc.vec.List

fn run(): i32 throws Error {
    var source = vec.new<u8>()
    source.extend_from_slice([104u8, 105u8])
    var input = std.io.Cursor<List<u8>>.new(source)
    var output = std.io.Cursor<List<u8>>.new(vec.new<u8>())
    let copied = try std.io.`copy`(mut input, mut output)
    if copied != 2usize { return 1 }
    let stored = output.into_inner()
    if stored.len() != 2usize || stored[0usize] != 104u8 { return 2 }

    var reader = std.io.BufferedReader.with_capacity(8usize, std.io.Cursor<List<u8>>.new(vec.new<u8>()))
    if reader.capacity() < 8usize { return 3 }
    var writer = std.io.BufferedWriter.with_capacity(8usize, vec.new<u8>())
    try writer.write_all([97u8])
    if writer.capacity() != 8usize { return 4 }
    let parts = writer.into_parts()
    if parts.1.len() != 1usize || parts.1[0usize] != 97u8 { return 5 }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(_) => 99
    }
}
