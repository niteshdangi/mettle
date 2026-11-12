// expect-error: ownership 8:5 live exclusive loan
import core.ops.DerefMut
import std.path.{PathBuf, path_buf_from_text}

fn main(): i32 {
    var owner = path_buf_from_text("Ab")
    let view = PathBuf.(DerefMut).deref_mut(mut owner)
    owner.clear()
    view.as_mut_os_str().make_ascii_uppercase()
    0
}
