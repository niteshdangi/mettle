// expect-error: type 6:5 unsatisfied interface bound 'Transferable'
// std.sync.mutex.MutexGuard is a negative impl (Rust: impl !Send), so a Send row cannot hold.
fn send_ok<T: Transferable>(): Unit {}
alias Guard = std.sync.mutex.MutexGuard<i32, region static>
fn main(): i32 {
    send_ok<Guard>()
    0
}
