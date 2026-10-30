
type Slot<region r> { value: read i32 from r }
fn assign<region r>(cell: read core::cell::RefCell<Slot<region r>>,
                     value: read i32 from r) {
    var guard = cell.borrow_mut()
    guard.get_mut().value = read value
}
fn main() {
    let first = 1
    let second = 42
    let cell = core::cell::RefCell::new(Slot(read first))
    assign(cell,read second)
    let guard = cell.borrow()
    if *guard.get_ref().value == 42 { 0 } else { 1 }
}
