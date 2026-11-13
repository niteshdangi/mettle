// expect-error: ownership 6:5 access or storage conflicts with a live exclusive loan
fn main(): i32 {
    var value = 42
    let cell = core.cell.Cell<i32>.from_mut(mut value)
    let before = cell.get()
    value = 7
    before + cell.get()
}
