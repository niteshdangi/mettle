// expect-error: type 6:5 unsatisfied interface bound 'Shareable'
// In Rust, NonNull is !Sync (negative auto-trait relation; blanket row evidence)
fn send_ok<T: Transferable>(): Unit {}
fn sync_ok<T: Shareable>(): Unit {}
fn main(): i32 {
    sync_ok<core.ptr.NonNull<i32>>()
    0
}
