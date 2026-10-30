// expect-error: ownership 7:5 access or storage lifetime conflicts with a live read loan

fn main() {
    var cell = core.cell.RefCell.new(42)
    let guard = cell.borrow()
    let value = *guard.get_ref()
    *cell.get_mut() = 0
    value
}
