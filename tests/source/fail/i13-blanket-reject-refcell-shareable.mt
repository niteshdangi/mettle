// expect-error: type 5:5 unsatisfied interface bound 'Shareable'
// In Rust, RefCell is !Sync (negative auto-trait relation; blanket row evidence)
fn sync_ok<T: Shareable>(): Unit {}
fn main(): i32 {
    sync_ok<core.cell.RefCell<i32>>()
    0
}
