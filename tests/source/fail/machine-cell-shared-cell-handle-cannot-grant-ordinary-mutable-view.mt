// expect-error: ownership 4:17 mut view requires a mutable place

fn wrong(read cell: core.cell.RefCell<i32>): Unit {
    let value = cell.get_mut()
}
fn main() { 0 }
