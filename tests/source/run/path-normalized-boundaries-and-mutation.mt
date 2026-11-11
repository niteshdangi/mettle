// profiles: debug release
import std.path.{PathBuf, path_from_text, path_buf_from_text}
import std.ffi.os_str_from_text

fn main(): i32 {
    let p = path_from_text("a/./b")
    let q = path_from_text("a/b")
    if !p.starts_with(q) || !p.ends_with(q) { return 1 }
    match take capture p.strip_prefix(q) {
        success(rest) => { if !rest.is_empty() { return 2 } },
        failure(_) => { return 3 }
    }
    let p = path_from_text("a/.")
    match p.file_name() {
        present(name) => { if name.to_str() != present("a") { return 4 } },
        none => { return 5 }
    }
    match p.parent() {
        present(parent) => { if !parent.is_empty() { return 6 } },
        none => { return 7 }
    }
    var empty = PathBuf.new()
    let _ = empty.set_file_name(os_str_from_text("x"))
    if empty.to_str() != present("x") { return 8 }
    let changed = path_from_text("base/file").with_file_name(os_str_from_text("/replacement"))
    if changed.to_str() != present("/replacement") { return 9 }
    var root = path_buf_from_text("/")
    root.add_extension(os_str_from_text("x"))
    if root.to_str() != present("/") { return 10 }
    var dotted = path_buf_from_text("a/.")
    let _ = dotted.set_extension(os_str_from_text("txt"))
    if dotted.to_str() != present("a.txt") { return 11 }
    0
}
