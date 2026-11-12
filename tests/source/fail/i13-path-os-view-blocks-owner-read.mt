// expect-error: ownership 7:8 live exclusive loan
import std.path.path_buf_from_text

fn main(): i32 {
    var owner = path_buf_from_text("Ab")
    let view = owner.as_mut_os_str()
    if owner.is_empty() { return 1 }
    view.make_ascii_lowercase()
    0
}
