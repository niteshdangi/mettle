// expect-error: ownership 9:17 access or storage lifetime conflicts with a live read loan

fn borrow<T>(cell: read core.cell.RefCell<T>): core.cell.Ref<T> from cell {
    cell.borrow()
}
fn main() {
    let cell = core.cell.RefCell.new(42)
    let guard = borrow(cell)
    let moved = cell
    0
}
