// expect-error: ownership 9:17 access or storage conflicts with a live read loan

import core.cell

fn main() {
    let cell = core.cell.RefCell.new([1i32, 2])
    let guard = core.cell.Ref<[i32; 2]>.map(cell.borrow(),
        fn(read value: [i32; 2]): read i32 from value { read value[0] })
    let moved = cell
    let _ = *guard.get_ref()
    0
}
