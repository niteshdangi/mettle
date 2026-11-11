import std.ffi.os_str_from_text

fn main(): i32 {
    var path = std.path.path_buf_from_text("file")
    match take std.panic.catch_panic(fn(): Unit {
        let _ = path.set_extension(os_str_from_text("x/y"))
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 1 }
    }
    match path.to_str() {
        present(text) => { if text != "file" { return 2 } },
        none => { return 2 }
    }
    match take std.panic.catch_panic(fn(): Unit {
        path.add_extension(os_str_from_text("x/y"))
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 3 }
    }
    match path.to_str() {
        present(text) => { if text != "file" { return 4 } },
        none => { return 4 }
    }
    0
}
