// expect-error: type 8:5 unsatisfied interface bound 'Transferable'
// expect-error: type 9:5 unsatisfied interface bound 'Shareable'
// expect-error: type 10:5 unsatisfied interface bound 'Transferable'
// expect-error: type 11:5 unsatisfied interface bound 'Shareable'
fn transferable<T: Transferable>() {}
fn shareable<T: Shareable>() {}
fn main() {
    transferable<core.cell.Ref<i32>>()
    shareable<core.cell.Ref<i32>>()
    transferable<core.cell.RefMut<i32>>()
    shareable<core.cell.RefMut<i32>>()
}
