// profiles: debug
import std.ffi
import std.path.{Path, path_buf_from_text}

fn main(): i32 {
    let raw: [u8; 3] = [97u8, 47u8, 255u8]
    let from_bytes = Path.new(raw)
    if !ffi.bytes_equal(from_bytes.as_bytes(), raw) { return 1 }

    let os = ffi.os_str(raw)
    let from_os = Path.new(os)
    if !ffi.bytes_equal(from_os.as_bytes(), raw) ||
        !from_os.as_os_str().same(os) {
        return 2
    }

    let text_path = Path.new("directory/file")
    if text_path.as_os_str().to_str().is_none() {
        return 3
    }

    let owner = path_buf_from_text("owner/path")
    let from_owner = Path.new(read owner)
    if !ffi.bytes_equal(from_owner.as_bytes(), owner.as_bytes()) ||
        !from_owner.as_os_str().same(owner.as_os_str()) {
        return 4
    }
    0
}
