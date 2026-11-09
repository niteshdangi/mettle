// expect-error: type 6:5 unsatisfied interface bound 'Transferable'
// std.sync.rwlock.WriteGuard is a negative impl (Rust: impl !Send), so a Send row cannot hold.
fn send_ok<T: Transferable>(): Unit {}
alias Guard = std.sync.rwlock.WriteGuard<i32, region static>
fn main(): i32 {
    send_ok<Guard>()
    0
}
