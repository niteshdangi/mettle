// PathInput accepts Path, PathBuf, OsStr and OsString without conversion;
// [u8].bytes() yields Copy bytes.
import std::path;
import std::path::PathInput;
fn total(p: read PathInput): usize { p.as_path().as_bytes().len() }
fn main(): i32 {
    let buf = path::path_buf_from_text("a/b")
    let os = std::ffi::os_string_from_text("abcd")
    let a = total(buf) + total(os) + total(os.as_os_str()) + total(buf.as_path())
    if a != 3usize + 4usize + 4usize + 3usize { return 1 }
    var sum = 0u32
    let data = [1u8, 2u8, 3u8]
    for b in data.bytes() { sum += b as u32 }
    if sum == 6u32 { 0 } else { 2 }
}
