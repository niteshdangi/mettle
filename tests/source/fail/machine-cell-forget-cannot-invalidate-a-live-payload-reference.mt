// expect-error: ownership 7:21 access or storage conflicts with a live read loan

fn main() {
    let cell = core.cell.RefCell.new(42)
    let guard = cell.borrow()
    let value = guard.get_ref()
    core.mem.forget(guard)
    *value
}
