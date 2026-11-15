
static mut CELL: core.cell.Cell<i32> = core.cell.Cell.new(0)
static mut STATE: core.cell.RefCell<i32> = core.cell.RefCell.new(41)
static POINTER: core.sync.atomic.AtomicPtr<u8> =
    core.sync.atomic.AtomicPtr<u8>.new(core.ptr.null_mut<u8>())
static EMPTY: core.cell.UnsafeCell<core.cell.RefCell<i32>?> =
    core.cell.UnsafeCell.new(none)
fn main() {
    unsafe {
        if !POINTER.load(core.sync.atomic.Ordering.Relaxed).is_null() {
            return 1
        }
        match read *EMPTY.get() {
            none => {},
            present(_) => { return 2 }
        }
        CELL.set(42)
        {
            var guard = STATE.borrow_mut()
            *guard.get_mut() += 1
        }
        let value = STATE.borrow()
        if CELL.get() == 42 && *value.get_ref() == 42 { 0 } else { 1 }
    }
}
