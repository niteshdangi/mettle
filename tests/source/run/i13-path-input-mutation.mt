// profiles: debug release
import alloc.string.String
import std.ffi.os_string_from_text
import std.path.{path_buf_from_text, path_from_text}

fn main(): i32 {
    let base = path_from_text("base/file")
    let relative = path_buf_from_text("child/../leaf")
    let joined = base.join(read relative)
    if !joined.as_path().same(path_from_text("base/file/child/../leaf")) { return 1 }
    if !relative.as_path().same(path_from_text("child/../leaf")) { return 2 }

    let replacement = os_string_from_text("/absolute")
    let replaced = joined.join(read replacement)
    if !replaced.as_path().same(path_from_text("/absolute")) { return 3 }

    var buffer = path_buf_from_text("start")
    let text = String("dir/file")
    buffer.push(read text)
    if !buffer.as_path().same(path_from_text("start/dir/file")) { return 4 }
    let name = path_buf_from_text("nested/name")
    let _ = buffer.set_file_name(read name)
    if !buffer.as_path().same(path_from_text("start/dir/nested/name")) { return 5 }

    let renamed = buffer.with_file_name("/replacement")
    if !renamed.as_path().same(path_from_text("/replacement")) { return 6 }
    if !buffer.as_path().same(path_from_text("start/dir/nested/name")) { return 7 }
    0
}
