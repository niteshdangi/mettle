import std.io.Error
import std.path.path_from_text

fn run(): i32 throws Error {
    let root = path_from_text("i13-fs-copy-aliases")
    let source = path_from_text("i13-fs-copy-aliases/source")
    let destination = path_from_text("i13-fs-copy-aliases/destination")
    let linked = path_from_text("i13-fs-copy-aliases/alias")
    try std.fs.create_dir(root)
    try std.fs.write(source, "source".as_bytes())
    try std.fs.set_permissions(source, std.fs.permissions_from_mode(416u32))
    try std.fs.write(destination, "longer destination".as_bytes())

    assert(try std.fs.`copy`(source, destination) == 6u64, "copy replaces destination")
    let copied = try std.fs.`read`(destination)
    assert(copied.as_slice() == "source".as_bytes(), "copy preserves bytes")
    assert(((try std.fs.metadata(destination)).permissions().mode() & 511u32) == 416u32,
        "copy preserves source permissions")

    assert(try std.fs.`copy`(source, source) == 0u64, "same path can truncate the source")
    assert((try std.fs.metadata(source)).len() == 0u64, "same path was truncated")

    try std.fs.write(source, "again".as_bytes())
    try std.fs.hard_link(source, linked)
    assert(try std.fs.`copy`(source, linked) == 0u64, "hard-linked destination aliases source")
    assert((try std.fs.metadata(source)).len() == 0u64, "hard link truncates the source")

    try std.fs.remove_file(linked)
    try std.fs.remove_file(destination)
    try std.fs.remove_file(source)
    try std.fs.remove_dir(root)
    0
}

fn main(): i32 {
    match take capture run() { success(code) => code, failure(_) => 100 }
}
