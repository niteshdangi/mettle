
fn borrow<T>(cell: read core.cell.RefCell<T>): core.cell.Ref<T> from cell {
    cell.borrow()
}
fn borrow_mut<T>(cell: read core.cell.RefCell<T>): core.cell.RefMut<T> from cell {
    cell.borrow_mut()
}
fn main() {
    let cell = core.cell.RefCell.new(40)
    { var guard = borrow_mut(cell); *guard.get_mut() += 2 }
    let guard = borrow(cell)
    if *guard.get_ref() == 42 { 0 } else { 1 }
}
