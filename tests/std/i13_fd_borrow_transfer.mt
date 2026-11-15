import std.io
import std.io.{Error, Reader, Writer}
import std.os.fd.{AsFd, AsRawFd, FromRawFd, IntoRawFd}

fn run(): i32 throws Error {
    let (reader, writer) = try io.pipe()
    let reader_fd = reader.as_fd()
    let writer_fd = writer.as_fd()
    if reader_fd.as_raw_fd() != reader.as_raw_fd() ||
        writer_fd.as_raw_fd() != writer.as_raw_fd() { return 1 }
    let raw = writer.into_raw_fd()
    var restored = unsafe { io.PipeWriter.(FromRawFd).from_raw_fd(raw) }
    try restored.write_all([7u8])
    core.mem.drop(take restored)
    var reader = reader
    var byte = [0u8; 1]
    if try reader.read_some(mut byte) != 1usize || byte[0usize] != 7u8 { return 2 }
    if try reader.read_some(mut byte) != 0usize { return 3 }
    0
}

fn main(): i32 {
    match capture run() {
        success(code) => code,
        failure(error) => 99
    }
}
