// Whole-file helpers, OpenOptions modes, file metadata, copy, set_len, permissions and exclusive creation.
import std.io.{Error, ErrorKind, Reader, Writer}
import std.fs.SeekFrom
import std.path.path_from_text

fn run(): i32 throws Error {
    let root = path_from_text("fs-operations-scratch")
    if std.fs.exists(root) { try std.fs.remove_dir_all(root) }
    try std.fs.create_dir(root)
    let file = path_from_text("fs-operations-scratch/data.txt")

    try std.fs.write(file, "one".as_bytes())
    var appending = std.fs.OpenOptions.new()
    appending.append(true)
    appending.create(true)
    var appender = try appending.open(file)
    try appender.write_all("two".as_bytes())
    let grown = try appender.metadata()
    if grown.len() != 6u64 || !grown.is_file() || grown.is_dir() { return 1 }
    try appender.set_len(4u64)
    let shrunk = try appender.metadata()
    if shrunk.len() != 4u64 { return 2 }

    let text = try std.fs.read_to_string(file)
    if text.len() != 4usize { return 3 }
    let content = try std.fs.`read`(file)
    if content.len() != 4usize || content[3usize] != 116u8 { return 4 }

    let copied = path_from_text("fs-operations-scratch/copy.txt")
    let copied_bytes = try std.fs.`copy`(file, copied)
    if copied_bytes != 4u64 { return 5 }
    let copied_text = try std.fs.read_to_string(copied)
    if copied_text.len() != 4usize { return 5 }

    var exclusive = std.fs.OpenOptions.new()
    exclusive.write(true)
    exclusive.create_new(true)
    let clash = capture exclusive.open(file)
    match take clash {
        success(_) => { return 6 },
        failure(e) => { if !e.kind().is(ErrorKind.AlreadyExists) { return 6 } }
    }

    try std.fs.rename(copied, path_from_text("fs-operations-scratch/moved.txt"))
    let moved = try std.fs.metadata(path_from_text("fs-operations-scratch/moved.txt"))
    if moved.len() != 4u64 || std.fs.exists(copied) { return 7 }

    var perms = std.fs.permissions_from_mode(420u32)
    if perms.readonly() { return 8 }
    perms.set_readonly(true)
    if !perms.readonly() { return 9 }
    try std.fs.set_permissions(path_from_text("fs-operations-scratch/moved.txt"), perms)
    let locked = try std.fs.metadata(path_from_text("fs-operations-scratch/moved.txt"))
    if !locked.permissions().readonly() { return 10 }
    try std.fs.set_permissions(path_from_text("fs-operations-scratch/moved.txt"), std.fs.permissions_from_mode(420u32))

    try std.fs.remove_file(path_from_text("fs-operations-scratch/moved.txt"))
    try std.fs.remove_file(file)
    try std.fs.remove_dir(root)
    if std.fs.exists(root) { return 11 }
    0
}

fn main(): i32 {
    let result = capture run()
    match take result {
        success(code) => code,
        failure(error) => 100
    }
}
