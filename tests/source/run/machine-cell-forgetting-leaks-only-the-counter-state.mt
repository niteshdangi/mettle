
fn main() {
    let cell = core.cell.RefCell.new(42)
    let guard = cell.borrow()
    core.mem.forget(guard)
    let blocked = cell.try_borrow_mut()
    let failed = match take blocked { success(guard) => false, failure(error) => true }
    let remaining = cell.borrow()
    if failed && *remaining.get_ref() == 42 { 0 } else { 1 }
}
