// expect-error: unsafe 5:13 operation requires an unsafe block or unsafe function

fn main() {
    let cell = core.cell.RefCell.new(1i32)
    let _ = cell.try_borrow_unguarded()
    0
}
