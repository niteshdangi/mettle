// expect-error-count: 1
// expect-error: ownership 6:5 access or storage conflicts with a live exclusive loan
fn main(): i32 {
    var value = 7i32
    let cell = core.cell.UnsafeCell.from_mut(mut value)
    value = 9
    *cell.get_mut()
}
