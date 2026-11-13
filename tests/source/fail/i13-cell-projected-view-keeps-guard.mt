// expect-error: ownership 10:19 access or storage conflicts with a live read loan

import core.cell

fn main(): i32 {
    let cell = core.cell.RefCell.new([1i32, 2])
    let guard = core.cell.Ref<[i32; 2]>.map(cell.borrow(),
        fn(read value: [i32; 2]): read i32 from value { read value[0] })
    let view = guard.get_ref()
    core.mem.drop(guard)
    *view
}
