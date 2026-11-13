// expect-error: ownership 4:71 access or storage conflicts with a live read loan

fn main() {
    let guard = { let cell = core.cell.RefCell.new(42); cell.borrow() }
    *guard.get_ref()
}
