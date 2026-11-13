// expect-error-count: 1
// profiles: debug release
// expect-error: ownership 16:17 access or storage conflicts with a live read loan
import core.cell
import core.convert.TryInto

fn identity<T: TryInto<T, Error = Never>>(take value: T): T {
    match take T.(TryInto<T>).try_into(value) {
        success(result) => result
    }
}

fn main(): i32 {
    let cell = core.cell.RefCell.new(7i32)
    let guard = identity(cell.borrow())
    let moved = cell
    *guard.get_ref()
}
