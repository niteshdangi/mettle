// expect-error: ownership 9:32 access or storage lifetime conflicts with a live exclusive loan

import core.cell

fn main() {
    let cell = core.cell.RefCell.new([1i32, 2])
    let _ = core.cell.RefMut<[i32; 2]>.map_split(cell.borrow_mut(),
        fn(mut value: [i32; 2]): (mut i32 from value, mut i32 from value) {
            (mut value[0], mut value[0])
        })
    0
}
