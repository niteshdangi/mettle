
fn total(cell: read core.cell.RefCell<[i32]>): i32 {
    let guard = cell.borrow()
    var total = 0
    for value in guard.get_ref() { total += value }
    total
}
fn main() {
    let cell = core.cell.RefCell.new([20,21])
    let slice: read core.cell.RefCell<[i32]> = read cell
    {
        var guard = slice.borrow_mut()
        guard.get_mut()[1] += 1
    }
    if total(slice) == 42 { 0 } else { 1 }
}
