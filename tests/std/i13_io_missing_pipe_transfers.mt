import core.convert.From
import std.io.{Error, PipeReader, PipeWriter, Reader, Writer}
import std.sys

extern "C" {
    unsafe fn pipe(descriptors: ptr<mut i32>): i32;
}

fn run(): i32 throws Error {
    var empty: [u8; 0] = []
    assert(try std.io.read_fd(-1i32, mut empty) == 0usize, "empty read does not access descriptor")
    assert(try std.io.write_fd(-1i32, read empty) == 0usize, "empty write does not access descriptor")
    var descriptors = [-1i32; 2]
    if unsafe { pipe(core.ptr.from_mut(mut descriptors).cast<i32>()) } != 0i32 {
        throw std.io.last_os_error()
    }
    let input = unsafe { sys.OwnedFd.from_raw_fd(descriptors[0usize]) }
    let output = unsafe { sys.OwnedFd.from_raw_fd(descriptors[1usize]) }
    let reader = PipeReader.(From<sys.OwnedFd>).from(input)
    let writer = PipeWriter.(From<sys.OwnedFd>).from(output)
    let input_again = sys.OwnedFd.(From<PipeReader>).from(reader)
    let output_again = sys.OwnedFd.(From<PipeWriter>).from(writer)
    assert(input_again.as_raw_fd() == descriptors[0usize], "reader transfer does not duplicate")
    assert(output_again.as_raw_fd() == descriptors[1usize], "writer transfer does not duplicate")
    var reader_again = PipeReader.(From<sys.OwnedFd>).from(input_again)
    var writer_again = PipeWriter.(From<sys.OwnedFd>).from(output_again)
    try writer_again.write_all("pipe".as_bytes())
    try writer_again.flush()
    var bytes = [0u8; 8]
    assert(try reader_again.read_some(mut bytes) == 4usize, "pipe read preserves partial progress")
    assert(bytes[0usize] == 112u8 && bytes[3usize] == 101u8, "ownership roundtrip preserves pipe data")
    core.mem.drop(take writer_again)
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
