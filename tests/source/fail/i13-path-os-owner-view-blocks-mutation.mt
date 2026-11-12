// expect-error: ownership 7:5 live exclusive loan
import std.path.path_buf_from_text

fn main(): i32 {
    var owner = path_buf_from_text("base")
    let native = owner.as_mut_os_string()
    owner.clear()
    native.clear()
    0
}
