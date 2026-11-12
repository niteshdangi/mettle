// profiles: debug release
import alloc.boxed.Box
import core.convert.From
import std.ffi.{OsString, bytes_equal, os_str_from_text}
import std.path.{Path, PathBuf, path_buf_from_bytes, path_from_text}

const EMPTY_PATH: PathBuf = PathBuf.new()

fn main(): i32 {
    if !EMPTY_PATH.is_empty() { return 1 }
    let input: [u8; 4] = [65u8, 47u8, 255u8, 90u8]
    var original = path_buf_from_bytes(read input)
    original.reserve(64usize)
    let original_pointer = original.as_bytes().as_ptr()
    let original_capacity = original.capacity()
    let native = original.into_os_string()
    if native.as_bytes().as_ptr() != original_pointer ||
        native.capacity() != original_capacity { return 2 }
    var owner = PathBuf.(From<OsString>).from(take native)
    if owner.as_bytes().as_ptr() != original_pointer ||
        owner.capacity() != original_capacity { return 3 }

    {
        let native = owner.as_mut_os_string()
        native.reserve(original_capacity + 32usize)
        native.make_ascii_lowercase()
        native.push(os_str_from_text("/tail"))
    }
    let appended: [u8; 9] = [97u8, 47u8, 255u8, 122u8, 47u8, 116u8, 97u8, 105u8, 108u8]
    if owner.capacity() <= original_capacity || !bytes_equal(owner.as_bytes(), read appended) {
        return 4
    }
    if !owner.pop() { return 5 }
    if !owner.set_extension(os_str_from_text("bin")) { return 6 }
    let changed: [u8; 8] = [97u8, 47u8, 255u8, 122u8, 46u8, 98u8, 105u8, 110u8]
    if !bytes_equal(owner.as_bytes(), read changed) { return 7 }
    let changed_pointer = owner.as_bytes().as_ptr()
    let changed_capacity = owner.capacity()
    let native = owner.into_os_string()
    if native.as_bytes().as_ptr() != changed_pointer ||
        native.capacity() != changed_capacity { return 8 }
    let owned = PathBuf.(From<OsString>).from(take native)
    let boxed = owned.into_boxed_path()
    let unboxed = PathBuf.(From<Box<Path>>).from(take boxed)
    if !bytes_equal(unboxed.as_bytes(), read changed) { return 9 }

    var empty = PathBuf.new()
    empty.as_mut_os_string().push(os_str_from_text("base"))
    empty.push(path_from_text("tail"))
    if empty.to_str() != present("base/tail") { return 10 }
    match take capture path_buf_from_bytes(read input).into_string() {
        success(_) => { return 11 },
        failure(error) => {
            if !bytes_equal(error.bytes.as_slice(), read input) { return 12 }
        }
    }
    0
}
