// expect-error: type 6:5 unsatisfied interface bound 'Transferable'
// In Rust, NonNull is !Send (negative auto-trait relation; blanket row evidence)
fn send_ok<T: Transferable>(): Unit {}
fn sync_ok<T: Shareable>(): Unit {}
fn main(): i32 {
    send_ok<core.ptr.NonNull<i32>>()
    0
}
