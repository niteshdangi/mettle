// io.Error keeps the raw OS error number unchanged and derives a portable kind.
import std.io.{Error, ErrorKind, Reader}
import std.path.path_from_text

fn run(): i32 throws Error {
    // Any errno round-trips exactly, whether or not it maps to a kind.
    var n = 1
    while n < 200 {
        let e = std.io.from_raw_os_error(n)
        if e.raw_os_error() != present(n) || !e.is_os() { return 1 }
        n += 1
    }
    let associated = Error.from_raw_os_error(2)
    if associated.raw_os_error() != present(2) || !associated.kind().is(ErrorKind.NotFound) {
        return 22
    }
    if !std.io.from_raw_os_error(2).kind().is(ErrorKind.NotFound) { return 2 }
    if !std.io.from_raw_os_error(13).kind().is(ErrorKind.PermissionDenied) { return 3 }
    if !std.io.from_raw_os_error(17).kind().is(ErrorKind.AlreadyExists) { return 4 }
    if !std.io.from_raw_os_error(32).kind().is(ErrorKind.BrokenPipe) { return 5 }
    if !std.io.from_raw_os_error(22).kind().is(ErrorKind.InvalidInput) { return 6 }
    if !ErrorKind.ArgumentListTooLong.is(ErrorKind.ArgumentListTooLong) ||
       !ErrorKind.TooManyOpenFiles.is(ErrorKind.TooManyOpenFiles) ||
       !ErrorKind.StorageFull.is(ErrorKind.StorageFull) { return 21 }
    // Errno values with the same number on Linux and macOS classify to the
    // remaining kinds; unmapped numbers stay `Other`.
    if !std.io.from_raw_os_error(7).kind().is(ErrorKind.ArgumentListTooLong) { return 30 }
    if !std.io.from_raw_os_error(18).kind().is(ErrorKind.CrossesDevices) { return 31 }
    if !std.io.from_raw_os_error(26).kind().is(ErrorKind.ExecutableFileBusy) { return 32 }
    if !std.io.from_raw_os_error(27).kind().is(ErrorKind.FileTooLarge) { return 33 }
    if !std.io.from_raw_os_error(5).kind().is(ErrorKind.InputOutputError) { return 34 }
    if !std.io.from_raw_os_error(29).kind().is(ErrorKind.NotSeekable) { return 35 }
    if !std.io.from_raw_os_error(30).kind().is(ErrorKind.ReadOnlyFilesystem) { return 36 }
    if !std.io.from_raw_os_error(16).kind().is(ErrorKind.ResourceBusy) { return 37 }
    if !std.io.from_raw_os_error(28).kind().is(ErrorKind.StorageFull) { return 38 }
    if !std.io.from_raw_os_error(31).kind().is(ErrorKind.TooManyLinks) { return 39 }
    if !std.io.from_raw_os_error(24).kind().is(ErrorKind.TooManyOpenFiles) { return 40 }
    if !std.io.from_raw_os_error(199).kind().is(ErrorKind.Other) { return 41 }
    // A kind-only error has no OS number.
    let k = std.io.from_kind(ErrorKind.UnexpectedEof)
    match k.raw_os_error() { present(c) => { return 7 }, none => {} }
    if k.is_os() { return 7 }
    // An overridden kind keeps the number.
    let t = std.io.with_kind(35, ErrorKind.TimedOut)
    if t.raw_os_error() != present(35) || !t.kind().is(ErrorKind.TimedOut) { return 8 }
    // Messages come from the C library for OS errors.
    if std.io.from_raw_os_error(2).message().len() == 0usize { return 9 }

    // Failures raised by real system calls carry their errno.
    let missing = capture std.fs.open(path_from_text("no-such-file"))
    match take missing {
        success(f) => { return 10 },
        failure(e) => { if e.raw_os_error() != present(2) || !e.kind().is(ErrorKind.NotFound) { return 11 } }
    }
    let made = capture std.fs.create_dir(path_from_text("d"))
    if made.is_failure() { return 12 }
    let again = capture std.fs.create_dir(path_from_text("d"))
    match take again {
        success(u) => { return 13 },
        failure(e) => { if e.raw_os_error() != present(17) || !e.kind().is(ErrorKind.AlreadyExists) { return 14 } }
    }
    // Reading a directory as a file reports EISDIR.
    let dir = try std.fs.open(path_from_text("d"))
    var d = dir
    var buf = [0u8; 4]
    let bad = capture d.read_some(buf)
    match take bad {
        success(c) => { return 15 },
        failure(e) => { if e.raw_os_error() != present(21) || !e.kind().is(ErrorKind.IsADirectory) { return 16 } }
    }
    // The last OS error is what the failing call set.
    let nested = capture std.fs.open(path_from_text("d/x/y"))
    match take nested {
        success(f) => { return 17 },
        failure(e) => { if e.raw_os_error() != present(2) { return 18 } }
    }
    if Error.last_os_error().raw_os_error() != present(2) { return 23 }
    // NUL bytes cannot be passed to the OS.
    let nul: [u8; 3] = [97u8, 0u8, 98u8]
    let rejected = capture std.fs.open(std.path.path(nul))
    match take rejected {
        success(f) => { return 19 },
        failure(e) => { if !e.kind().is(ErrorKind.InvalidInput) || e.is_os() { return 20 } }
    }
    0
}

fn main(): i32 {
    let r = capture run()
    match take r { success(code) => code, failure(e) => 100 }
}
