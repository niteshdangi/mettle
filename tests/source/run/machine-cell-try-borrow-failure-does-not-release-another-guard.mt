
fn main() {
    let cell = core::cell::RefCell::new(42)
    {
        var exclusive = cell.borrow_mut()
        { let failed = cell.try_borrow() }
        { let failed = cell.try_borrow_mut() }
        let failed = cell.try_borrow()
        let blocked = match take failed { success(guard) => false, failure(error) => true }
        if !blocked || *exclusive.get_mut() != 42 { return 1 }
    }
    { let guard = cell.borrow() }
    var guard = cell.borrow_mut()
    if *guard.get_mut() == 42 { 0 } else { 2 }
}
