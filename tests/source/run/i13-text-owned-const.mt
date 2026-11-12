// profiles: debug release
import alloc.string
import std.path.PathBuf

const fn empty_string(): bool {
    let empty = match core.text.from_utf8([0u8; 0]) {
        success(text) => text,
        failure(_) => { return false }
    }
    var value = string.new()
    if value.as_mut_str().len() != 0usize { return false }
    let bytes = unsafe { value.as_mut_vec() }
    if bytes.as_mut_slice().len() != 0usize { return false }
    if !value.eq_ignore_ascii_case(empty) { return false }
    if value.trim_ascii_start().len() != 0usize ||
        value.trim_ascii_end().len() != 0usize ||
        value.trim_ascii().len() != 0usize { return false }
    match value.split_at_checked(1usize) { present(_) => { return false }, none => () }
    match value.split_at_checked(0usize) {
        present(parts) => if parts.0.len() != 0usize || parts.1.len() != 0usize { return false },
        none => { return false }
    }
    let split = value.split_at_mut(0usize)
    split.0.len() == 0usize && split.1.len() == 0usize
}

const EMPTY_STRING: bool = empty_string()
const EMPTY_PATH: PathBuf = PathBuf.new()
fn main(): i32 {
    if EMPTY_STRING && EMPTY_PATH.as_bytes().len() == 0usize { 0 } else { 1 }
}
