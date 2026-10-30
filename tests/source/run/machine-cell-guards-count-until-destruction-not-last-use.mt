
fn main() {
    let cell = core.cell.RefCell.new(42)
    {
        let first = cell.borrow()
        let second = first.clone()
        if *first.get_ref() != 42 || *second.get_ref() != 42 { return 1 }
        let blocked = cell.try_borrow_mut()
        if match take blocked { success(guard) => false, failure(error) => true } {
        } else { return 2 }
    }
    {
        var exclusive = cell.borrow_mut()
        *exclusive.get_mut() = 40
        let blocked = cell.try_borrow()
        if match take blocked { success(guard) => false, failure(error) => true } {
        } else { return 3 }
        *exclusive.get_mut() += 2
    }
    let value = cell.borrow()
    if *value.get_ref() == 42 { 0 } else { 4 }
}
