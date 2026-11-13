import alloc.vec
import std.io.{Error, ErrorKind, Reader, Seek, Writer}
import std.path.path_from_text
import std.fs.{File, FileType, OpenOptions, SeekFrom, TryLockError}

fn run(): i32 throws Error {
    if !FileType.File.is_file() || !FileType.Directory.is_dir() ||
        !FileType.Symlink.is_symlink() {
        return 15
    }

    let directory = path_from_text("i13-fs-create-options")
    let file_path = path_from_text("i13-fs-create-options/nested/data")
    try std.fs.create_dir_all(path_from_text("i13-fs-create-options/nested"))

    var file = try std.fs.create_new(file_path)
    try file.write_all("first".as_bytes())
    let initial_metadata = try file.metadata()
    let initial_type = initial_metadata.file_type()
    if !initial_type.is_file() || initial_metadata.is_symlink() { return 1 }
    if initial_metadata.len() != 5u64 { return 2 }
    let modified = initial_metadata.modified()
    core.mem.drop(take file)
    var created = try std.fs.create(file_path)
    try created.write_all("created".as_bytes())
    {
        var viewed = read created
        try viewed.write_all("!".as_bytes())
    }
    if try created.metadata().len() != 8u64 { return 16 }
    core.mem.drop(take created)
    try std.fs.write(file_path, "first".as_bytes())

    match take capture std.fs.create_new(file_path) {
        success(duplicate) => { core.mem.drop(take duplicate); return 3 },
        failure(error) => {
            if !error.kind().is(ErrorKind.AlreadyExists) { return 4 }
        }
    }

    var read_only_options = File.options()
    read_only_options.`read`(true)
    var read_only = try read_only_options.open(file_path)
    var first_byte = [0u8]
    if try read_only.read_some(first_byte) != 1usize || first_byte[0usize] != 102u8 {
        return 30
    }
    core.mem.drop(take read_only)

    var invalid_read_truncate = File.options()
    invalid_read_truncate.`read`(true)
    invalid_read_truncate.truncate(true)
    match take capture invalid_read_truncate.open(file_path) {
        success(invalid) => { core.mem.drop(take invalid); return 31 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 32 }
        }
    }
    if (try std.fs.read_to_string(file_path)).as_text() != "first" { return 33 }
    var append_truncate = File.options()
    append_truncate.write(true)
    append_truncate.append(true)
    append_truncate.truncate(true)
    match take capture append_truncate.open(file_path) {
        success(invalid) => { core.mem.drop(take invalid); return 34 },
        failure(error) => {
            if !error.kind().is(ErrorKind.InvalidInput) { return 35 }
        }
    }
    if (try std.fs.read_to_string(file_path)).as_text() != "first" { return 36 }

    var options = File.options()
    options.`read`(true)
    options.truncate(true)
    options.write(true)
    var opened = try options.open(file_path)
    require_file_io_views(mut opened)
    if (try opened.metadata()).len() != 0u64 { return 5 }
    var contents = vec.new<u8>()
    if try opened.read_to_end(contents) != 0usize { return 6 }
    try opened.write_all("seek".as_bytes())
    if try opened.seek(SeekFrom.Start(0u64)) != 0u64 { return 16 }
    if try opened.stream_position() != 0u64 { return 18 }
    try opened.seek_relative(1i64)
    if try opened.stream_position() != 1u64 { return 19 }
    try opened.rewind()
    var seek_bytes = [0u8; 4]
    try opened.read_exact(seek_bytes)
    if seek_bytes[0usize] != 115u8 || seek_bytes[3usize] != 107u8 {
        return 17
    }
    {
        var file_view = read opened
        if try file_view.seek(SeekFrom.Start(0u64)) != 0u64 { return 20 }
        var reference_byte = [0u8; 1]
        if try file_view.read_some(reference_byte) != 1usize ||
            reference_byte[0usize] != 115u8 {
            return 21
        }
        if try file_view.write_some("x".as_bytes()) != 1usize { return 22 }
    }
    core.mem.drop(take opened)

    var first_lock = try std.fs.open(file_path)
    var second_lock = try std.fs.open(file_path)
    try first_lock.lock()
    match take capture second_lock.try_lock() {
        success(_) => { return 13 },
        failure(TryLockError.WouldBlock) => {},
        failure(_) => { return 14 }
    }
    try first_lock.unlock()
    match take capture first_lock.try_lock_shared() {
        success(_) => {},
        failure(_) => { return 100 }
    }
    match take capture second_lock.try_lock_shared() {
        success(_) => {},
        failure(_) => { return 100 }
    }
    try first_lock.unlock()
    try second_lock.unlock()
    core.mem.drop(take first_lock)
    core.mem.drop(take second_lock)

    let canonical = try std.fs.canonicalize(file_path)
    if canonical.as_path().as_bytes().len() == 0usize { return 7 }
    {
        var entries = try std.fs.read_dir(path_from_text("i13-fs-create-options/nested"))
        match try entries.next_entry() {
            present(entry) => {
                if entry.file_name().as_encoded_bytes().len() != 4usize { return 8 }
                let entry_type = try entry.file_type()
                let entry_metadata = try entry.metadata()
                if !entry_type.is_file() { return 9 }
                if entry_metadata.len() != 4u64 { return 10 }
                if entry.path().as_path().as_bytes().len() == 0usize { return 11 }
            },
            none => { return 12 }
        }
    }
    try std.fs.remove_file(file_path)
    try std.fs.remove_dir(path_from_text("i13-fs-create-options/nested"))
    try std.fs.remove_dir(directory)
    0
}

fn require_file_io_views<T: Reader + Writer + Seek>(mut value: T) {}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(_) => 100
    }
}
