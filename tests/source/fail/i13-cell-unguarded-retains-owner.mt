// expect-error: ownership 9:17 access or storage lifetime conflicts with a live read loan

fn main() {
    let cell = core.cell.RefCell.new(1i32)
    let view = match unsafe { cell.try_borrow_unguarded() } {
        success(value) => value,
        failure(_) => { return 0 }
    }
    let moved = cell
    if *view != 1 { return 1 }
    0
}
