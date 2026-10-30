
fn main() {
    let cell = core.cell.RefCell.new(42)
    {
        let first = cell.borrow()
        let second = first.clone()
        let payload = first.get_ref()
        core.mem.forget(second)
        if *payload != 42 { return 1 }
    }
    let blocked = cell.try_borrow_mut()
    if match take blocked { success(guard) => false, failure(error) => true } {
        0
    } else { 2 }
}
