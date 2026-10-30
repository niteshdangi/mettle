// expect-error: ownership 4:17 exclusive borrow requires a mutable place

fn wrong(cell: read core::cell::RefCell<i32>): Unit {
    let value = cell.get_mut()
}
fn main() { 0 }
