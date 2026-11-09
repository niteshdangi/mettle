import alloc.vec
import std.io.{Error, Reader, Writer}

fn run(): i32 throws Error {
    let bytes = "copy bytes".as_bytes()
    var reader = std.io.slice_reader(bytes)
    var output = vec.new<u8>()
    if try std.io.`copy`(mut reader, mut output) != 10u64 { return 1 }
    if output.len() != 10usize || output[0usize] != 99u8 ||
        output[9usize] != 115u8 {
        return 2
    }
    if try output.write_some("end".as_bytes()) != 3usize ||
        output.len() != 13usize {
        return 3
    }

    var formatted = vec.new<u8>()
    try formatted.write(f"line")
    try formatted.flush()
    if formatted.len() != 4usize || formatted[0usize] != 108u8 ||
        formatted[3usize] != 101u8 {
        return 4
    }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
