// expect-exit: 101
// expect-stderr: panicked: out of cheese
// expect-stdout: before\n
// The default hosted panic prints the message to stderr and exits with 101.
fn main(): i32 {
    std.io.print("before\n")
    if std.panic.panicking() { return 1 }
    panic("out of cheese")
    0
}
