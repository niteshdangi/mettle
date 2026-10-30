
fn main() {
    let cell = core.cell.RefCell.new(42)
    {
        let guard = cell.borrow()
        let inspect = take fn(): i32 { *guard.get_ref() }
        if inspect() != 42 { return 1 }
    }
    var guard = cell.borrow_mut()
    if *guard.get_mut() == 42 { 0 } else { 2 }
}
