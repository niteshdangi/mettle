import core.convert.From
import std.io.{Error, IsTerminal, PipeReader, PipeWriter, Reader, Writer}
import std.sys

fn run(): i32 throws Error {
    var empty: [u8; 0] = []
    assert(try std.io.read_fd(-1i32, mut empty) == 0usize, "empty read does not access descriptor")
    assert(try std.io.write_fd(-1i32, read empty) == 0usize, "empty write does not access descriptor")
    let (reader, writer) = try std.io.pipe()
    let reader_clone = try reader.try_clone()
    let writer_clone = try writer.try_clone()
    let input = sys.OwnedFd.(From<PipeReader>).from(reader)
    let output = sys.OwnedFd.(From<PipeWriter>).from(writer)
    let cloned_input = sys.OwnedFd.(From<PipeReader>).from(reader_clone)
    let cloned_output = sys.OwnedFd.(From<PipeWriter>).from(writer_clone)
    let input_fd = input.as_raw_fd()
    let output_fd = output.as_raw_fd()
    assert(input_fd != cloned_input.as_raw_fd() &&
        output_fd != cloned_output.as_raw_fd(), "pipe clones own distinct descriptors")
    assert(!input.is_terminal() && !output.is_terminal(), "pipe descriptors are not terminals")
    let reader = PipeReader.(From<sys.OwnedFd>).from(input)
    let writer = PipeWriter.(From<sys.OwnedFd>).from(output)
    let input_again = sys.OwnedFd.(From<PipeReader>).from(reader)
    let output_again = sys.OwnedFd.(From<PipeWriter>).from(writer)
    assert(input_again.as_raw_fd() == input_fd, "reader transfer does not duplicate")
    assert(output_again.as_raw_fd() == output_fd, "writer transfer does not duplicate")
    var reader_again = PipeReader.(From<sys.OwnedFd>).from(input_again)
    var writer_again = PipeWriter.(From<sys.OwnedFd>).from(output_again)
    var writer_clone_again = PipeWriter.(From<sys.OwnedFd>).from(cloned_output)
    try writer_again.write_all("pi".as_bytes())
    try writer_clone_again.write_all("pe".as_bytes())
    try writer_again.flush()
    var bytes = [0u8; 4]
    try reader_again.read_exact(mut bytes)
    assert(bytes[0usize] == 112u8 && bytes[3usize] == 101u8, "ownership roundtrip preserves pipe data")
    core.mem.drop(take writer_clone_again)
    core.mem.drop(take writer_again)
    core.mem.drop(take cloned_input)
    assert(try reader_again.read_some(mut bytes) == 0usize, "dropping the sole writer closes its endpoint")

    let read_only = sys.OwnedFd.(From<PipeReader>).from(reader_again)
    var wrong_writer = PipeWriter.(From<sys.OwnedFd>).from(read_only)
    match take capture wrong_writer.write_some("x".as_bytes()) {
        failure(error) => { assert(error.raw_os_error() == present(9i32), "access-mode failure preserves EBADF") },
        success(_) => { return 1 }
    }
    let restored_input = sys.OwnedFd.(From<PipeWriter>).from(wrong_writer)
    let mut_reader = PipeReader.(From<sys.OwnedFd>).from(restored_input)
    let final_owner = sys.OwnedFd.(From<PipeReader>).from(mut_reader)
    let raw = final_owner.as_raw_fd()
    core.mem.drop(take final_owner)
    match take capture std.io.read_fd(raw, mut bytes) {
        failure(error) => { assert(error.raw_os_error() == present(9i32), "final owner closes the endpoint") },
        success(_) => { return 2 }
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
