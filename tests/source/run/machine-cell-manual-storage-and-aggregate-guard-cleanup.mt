
fn main() {
    let cell = core::cell::RefCell::new(42)
    { let guards = [cell.borrow(),cell.borrow()] }
    {
        let wrapper = core::mem::ManuallyDrop::new(cell.borrow_mut())
        { let guard = wrapper.into_inner() }
    }
    { let guard = cell.borrow() }
    { let wrapper = core::mem::ManuallyDrop::new(cell.borrow_mut()) }
    let blocked = cell.try_borrow()
    if match take blocked { success(guard) => false, failure(error) => true } {
        0
    } else { 1 }
}
