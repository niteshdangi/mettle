// expect-error: ownership 5:5 returned view escapes local storage

fn wrong(cell: read core.cell.RefCell<i32>): read i32 from cell {
    let guard = cell.borrow()
    guard.get_ref()
}
fn main() { 0 }
