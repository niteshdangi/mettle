// expect-exit: 101
// expect-stdout: hook: boom\n
// A registered hook receives the message instead of the default report;
// the process still exits with 101.
unsafe extern "C" fn hook(message: ptr<read u8>, length: u64): Unit {
    std.io.print("hook: ")
    let b = unsafe { std.sys.write(1, message, length as usize) }
    std.io.print("\n")
}

fn main(): i32 {
    std.panic.set_hook(hook)
    panic("boom")
    0
}
