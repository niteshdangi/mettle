import core.fmt
import core.fmt.Debug
import core.ops.Deref
import core.text.Text
import std.path.{Path, PathBuf, path_buf_from_text, path_from_text}

fn debug_is<T: Debug + unsized>(read value: T, read expected: Text): bool {
    var buffer = [0u8; 64]
    var writer = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut writer, fmt.spec())
    match capture T.(Debug).fmt(value, mut formatter) {
        success(unit) => {},
        failure(error) => { return false }
    }
    let length = writer.len()
    match fmt.written_text(read buffer, length) {
        present(actual) => actual == expected,
        none => false
    }
}

fn main(): i32 {
    if !debug_is(path_from_text("/a/b"), "Path(\"/a/b\")") { return 1 }
    let owned = path_buf_from_text("/a/b")
    let view: read Path = PathBuf.(Deref).deref(owned)
    if view != path_from_text("/a/b") { return 2 }
    0
}
