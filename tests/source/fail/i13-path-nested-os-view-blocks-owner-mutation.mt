// expect-error: ownership 7:5 live exclusive loan
import std.path.{path_buf_from_text, path_from_text}

fn main(): i32 {
    var owner = path_buf_from_text("Ab")
    let view = owner.as_mut_path().as_mut_os_str()
    owner.push(path_from_text("tail"))
    view.make_ascii_uppercase()
    0
}
