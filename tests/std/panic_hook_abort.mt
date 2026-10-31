// expect-exit: -6
unsafe extern "C" fn panicking_hook(message: ptr<read u8>, length: u64): Unit {
    panic("panic from hook")
}

fn main(): i32 {
    std.panic.set_hook(panicking_hook)
    let _caught = std.panic.catch_panic(take fn(): i32 {
        panic("original panic")
        0
    })
    0
}
