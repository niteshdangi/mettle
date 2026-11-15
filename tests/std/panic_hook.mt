// expect-exit: 101
// expect-stdout: hook: boom\n
// A registered hook receives the borrowed context before the process exits.
unsafe extern "C" fn hook(raw: ptr<read std.panic.PanicHookInfo>): Unit {
    let info = unsafe { *raw }
    std.io.print("hook: ")
    match info.payload_as_str() {
        present(text) => std.io.print(text),
        none => std.io.print(" missing-payload")
    }
    match unsafe { info.location() } {
        present(location) => {
            if location.file_bytes().len() == 0usize || location.line() == 0u64 ||
                location.column() == 0u64 {
                std.io.print(" missing-location")
            }
        },
        none => std.io.print(" missing-location")
    }
    std.io.print("\n")
}

fn main(): i32 {
    std.panic.set_hook(hook)
    panic("boom")
    0
}
