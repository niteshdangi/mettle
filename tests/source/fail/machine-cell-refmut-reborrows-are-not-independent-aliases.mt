// expect-error: ownership 8:15 access or storage conflicts with a live exclusive loan

fn main() {
    let cell = core.cell.RefCell.new(42)
    var guard = cell.borrow_mut()
    let first = guard.get_mut()
    let second = guard.get_mut()
    *first += *second
    0
}
