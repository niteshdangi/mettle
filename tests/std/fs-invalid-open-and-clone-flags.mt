import std.io.{Error, ErrorKind}

extern "C" { unsafe fn fcntl(fd: i32, command: i32, ...): i32; }

fn run(): i32 throws Error {
    try std.fs.write("data", "keep".as_bytes())
    var options = std.fs.open_options()
    options.set_read(true)
    options.set_truncate(true)
    match take capture options.open("data") {
        failure(error) => { if !error.kind().is(ErrorKind.InvalidInput) { return 1 } },
        success(_) => { return 2 }
    }
    if (try std.fs.read_to_string("data")).as_text() != "keep" { return 3 }
    options.set_write(true)
    options.set_append(true)
    match take capture options.open("data") {
        failure(error) => { if !error.kind().is(ErrorKind.InvalidInput) { return 10 } },
        success(_) => { return 11 }
    }
    if (try std.fs.read_to_string("data")).as_text() != "keep" { return 12 }
    options.set_create_new(true)
    let _ = try options.open("new")
    try std.fs.create_dir_all("")
    let file = try std.fs.open("data")
    let clone = try file.try_clone()
    if (unsafe { fcntl(clone.as_raw_fd(), 1) } & 1) == 0 { return 4 }
    let _ = unsafe { std.sys.close(0) }
    let clone = try file.try_clone()
    if clone.as_raw_fd() < 3 { return 5 }
    if !std.io.from_raw_os_error(28).kind().is(ErrorKind.StorageFull) { return 6 }
    if !std.io.from_raw_os_error(30).kind().is(ErrorKind.ReadOnlyFilesystem) { return 7 }
    let nul = [0u8]
    match take capture std.fs.exists(std.path.path(nul)) {
        failure(error) => { if !error.kind().is(ErrorKind.InvalidInput) { return 8 } },
        success(_) => { return 9 }
    }
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
