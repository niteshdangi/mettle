// POSIX positional I/O preserves file bytes and does not move the shared cursor.
import std.ffi
import std.fs.{ FileExt, OpenOptions, SeekFrom }
import std.io.{ Error, ErrorKind }
import std.path.path_from_text

fn run(): i32 throws Error {
    let path = path_from_text("i13-positional-io")
    var options = OpenOptions.new()
    options.set_read(true)
    options.write(true)
    options.create(true)
    options.truncate(true)
    var file = try options.open(path)

    let payload: [u8; 4] = [65u8, 0u8, 255u8, 90u8]
    if try file.write_at(payload, 3u64) != 4usize { return 1 }
    if (try file.metadata()).len() != 7u64 { return 2 }
    if try file.seek(SeekFrom.Current(0i64)) != 0u64 { return 3 }

    let initial = try file.seek(SeekFrom.Start(1u64))
    if initial != 1u64 { return 4 }
    var read_back = [0u8; 4]
    if try file.read_at(read_back, 3u64) != 4usize { return 5 }
    if !ffi.bytes_equal(read_back, payload) { return 6 }

    var hole = [1u8; 3]
    if try file.read_at(hole, 0u64) != 3usize { return 7 }
    if hole[0usize] != 0u8 || hole[1usize] != 0u8 || hole[2usize] != 0u8 {
        return 8
    }

    let cursor = try file.seek(SeekFrom.Current(0i64))
    if cursor != 1u64 { return 9 }
    let trailer: [u8; 1] = [127u8]
    if try file.write_at(trailer, 7u64) != 1usize { return 10 }
    if try file.seek(SeekFrom.Current(0i64)) != 1u64 { return 11 }
    var eof = [0u8; 1]
    if try file.read_at(eof, 8u64) != 0usize { return 12 }

    {
        var cloned = try file.try_clone()
        if try cloned.seek(SeekFrom.Current(0i64)) != 1u64 { return 23 }
        if try cloned.seek(SeekFrom.Start(2u64)) != 2u64 { return 24 }
        if try file.seek(SeekFrom.Current(0i64)) != 2u64 { return 25 }
    }
    if try file.seek(SeekFrom.Start(1u64)) != 1u64 { return 26 }
    try file.sync_all()
    try file.sync_data()
    if try file.seek(SeekFrom.Current(0i64)) != 1u64 ||
        (try file.metadata()).len() != 8u64 {
        return 27
    }
    try file.set_permissions(std.fs.permissions_from_mode(384u32))
    if ((try file.metadata()).permissions().mode() & 511u32) != 384u32 {
        return 28
    }

    let invalid_read = capture file.read_at(eof, 9223372036854775808u64)
    match take invalid_read {
        success(count) => { return 13 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 14 }
        }
    }
    let invalid_write = capture file.write_at(payload, 9223372036854775808u64)
    match take invalid_write {
        success(count) => { return 15 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 16 }
        }
    }

    var empty = [0u8; 0]
    if try file.read_at(empty, 0u64) != 0usize ||
        try file.write_at(empty, 0u64) != 0usize {
        return 17
    }
    if try file.seek(SeekFrom.Current(0i64)) != 1u64 { return 18 }

    var read_options = OpenOptions.new()
    read_options.set_read(true)
    let read_only = try read_options.open(path)
    match take capture read_only.write_at(empty, 0u64) {
        success(_) => { return 19 },
        failure(error) => {
            if error.raw_os_error().is_none() { return 20 }
        }
    }
    var write_options = OpenOptions.new()
    write_options.write(true)
    let write_only = try write_options.open(path)
    match take capture write_only.read_at(empty, 0u64) {
        success(_) => { return 21 },
        failure(error) => {
            if error.raw_os_error().is_none() { return 22 }
        }
    }
    core.mem.drop(take read_only)
    core.mem.drop(take write_only)
    core.mem.drop(take file)
    try std.fs.remove_file(path)
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
