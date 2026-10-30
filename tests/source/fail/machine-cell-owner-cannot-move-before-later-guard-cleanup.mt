// expect-error: ownership 6:17 access or storage lifetime conflicts with a live read loan

fn main() {
    let cell = core::cell::RefCell::new(42)
    let guard = cell.borrow()
    let moved = cell
    0
}
