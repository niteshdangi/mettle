// expect-error: type 6:17 invalid primitive operation or operand types

fn main() {
    let cell = core::cell::RefCell::new(42)
    var guard = cell.borrow()
    let wrong = guard.get_mut()
    0
}
