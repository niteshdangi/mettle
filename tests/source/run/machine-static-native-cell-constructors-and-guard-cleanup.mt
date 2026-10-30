
static mut CELL: core.cell.Cell<i32> = core.cell.Cell.new(0)
static mut STATE: core.cell.RefCell<i32> = core.cell.RefCell.new(41)
fn main() {
    unsafe {
        CELL.set(42)
        {
            var guard = STATE.borrow_mut()
            *guard.get_mut() += 1
        }
        let value = STATE.borrow()
        if CELL.get() == 42 && *value.get_ref() == 42 { 0 } else { 1 }
    }
}
