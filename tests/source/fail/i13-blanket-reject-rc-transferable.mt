// expect-error: type 5:5 unsatisfied interface bound 'Transferable'
// In Rust, LocalShared is !Send (negative auto-trait relation; blanket row evidence)
fn send_ok<T: Transferable>(): Unit {}
fn main(): i32 {
    send_ok<alloc.rc.LocalShared<i32>>()
    0
}
