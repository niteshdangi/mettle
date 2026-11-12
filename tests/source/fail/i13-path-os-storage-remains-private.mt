// expect-error: name 6:13 private or restricted field 'v'
import std.ffi.os_string_from_text

fn main(): i32 {
    let owner = os_string_from_text("base")
    let _ = owner.v.len()
    0
}
