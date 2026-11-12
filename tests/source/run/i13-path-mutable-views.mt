// profiles: debug release
import core.ops.DerefMut
import std.ffi.bytes_equal
import std.path.{PathBuf, path_buf_from_bytes, path_from_text}

fn main(): i32 {
    let input: [u8; 4] = [65u8, 47u8, 255u8, 90u8]
    let lower: [u8; 4] = [97u8, 47u8, 255u8, 122u8]
    var owner = path_buf_from_bytes(read input)
    {
        let view = owner.as_mut_os_str()
        view.make_ascii_lowercase()
    }
    if !bytes_equal(owner.as_bytes(), read lower) { return 1 }
    {
        let path = owner.as_mut_path()
        let view = path.as_mut_os_str()
        view.make_ascii_uppercase()
    }
    if !bytes_equal(owner.as_bytes(), read input) { return 2 }
    {
        let path = PathBuf.(DerefMut).deref_mut(mut owner)
        path.as_mut_os_str().make_ascii_lowercase()
    }
    if !bytes_equal(owner.as_bytes(), read lower) { return 3 }
    owner.push(path_from_text("tail"))
    let appended: [u8; 9] = [97u8, 47u8, 255u8, 122u8, 47u8, 116u8, 97u8, 105u8, 108u8]
    if !bytes_equal(owner.as_bytes(), read appended) { return 4 }

    var empty = PathBuf.new()
    {
        let view = empty.as_mut_os_str()
        view.make_ascii_uppercase()
    }
    {
        let path = PathBuf.(DerefMut).deref_mut(mut empty)
        path.as_mut_os_str().make_ascii_lowercase()
    }
    if !empty.is_empty() { return 5 }
    empty.push(path_from_text("first"))
    if empty.to_str() != present("first") { return 6 }
    0
}
