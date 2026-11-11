fn main(): i32 {
    match take std.panic.catch_panic(fn(): Unit {
        unsafe {
            let _ = capture std.env.set_var(std.ffi.os_str_from_text(""), std.ffi.os_str_from_text("v"))
        }
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 1 }
    }
    match take std.panic.catch_panic(fn(): Unit {
        unsafe { let _ = capture std.env.remove_var(std.ffi.os_str_from_text("a=b")) }
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 2 }
    }
    0
}
