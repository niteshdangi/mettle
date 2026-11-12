// file: entry=present
import core.iter.Iterator
import std.io
import std.path.path_from_text
import std.sys

extern "C" {
    unsafe fn pipe(descriptors: ptr<mut i32>): i32;
}

fn run(): i32 throws io.Error {
    var empty: [u8; 0] = []
    if try io.read_fd(-1i32, mut empty) != 0usize ||
        try io.write_fd(-1i32, read empty) != 0usize { return 1 }
    var descriptors = [-1i32; 2]
    if unsafe { pipe(core.ptr.from_mut(descriptors).cast<i32>()) } != 0i32 {
        throw io.last_os_error()
    }
    let input = unsafe { sys.OwnedFd.from_raw_fd(descriptors[0usize]) }
    let output = unsafe { sys.OwnedFd.from_raw_fd(descriptors[1usize]) }
    if try io.write_fd(output.as_raw_fd(), [41u8, 42u8]) != 2usize { return 2 }
    var bytes = [0u8; 2]
    if try io.read_fd(input.as_raw_fd(), mut bytes) != 2usize ||
        bytes[0usize] != 41u8 || bytes[1usize] != 42u8 { return 3 }
    core.mem.drop(take output)
    if try io.read_fd(input.as_raw_fd(), mut bytes) != 0usize { return 4 }
    let path = path_from_text(".").to_path_buf()
    var entries = try std.fs.read_dir(read path)
    var count = 0usize
    while true {
        match take entries.next() {
            present(success(_)) => { count += 1usize },
            present(failure(error)) => { throw error },
            none => { break }
        }
    }
    if count == 0usize || entries.next().is_present() || entries.next().is_present() {
        return 5
    }
    if (try entries.next_entry()).is_present() { return 6 }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
