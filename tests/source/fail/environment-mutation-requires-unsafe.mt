// expect-error: unsafe 4:21 operation requires an unsafe block or unsafe function
fn main(): i32 {
    let name = std.ffi.os_str_from_text("METTLE_UNSAFE_REQUIRED")
    let _ = capture std.env.remove_var(name)
    0
}
