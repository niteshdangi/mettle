// expect-error: ownership 12:44 access or storage lifetime conflicts with a live read loan

type Slot<region r> { value: read i32 from r }
fn set<region r>(cell: read core::cell::RefCell<Slot<region r>>,
                 value: read i32 from r) {
    var guard = cell.borrow_mut()
    guard.get_mut().value = read value
}
fn main() {
    let first = 1
    let cell = core::cell::RefCell::new(Slot(read first))
    { let short = 42; set(cell,read short) }
    let guard = cell.borrow()
    *guard.get_ref().value
}
