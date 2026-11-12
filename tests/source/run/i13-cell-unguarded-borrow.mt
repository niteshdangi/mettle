// profiles: debug release

import core.cell

fn main(): i32 {
    let cell = core.cell.RefCell.new(41i32)
    {
        let view = match unsafe { cell.try_borrow_unguarded() } {
            success(value) => value,
            failure(_) => { return 1 }
        }
        if *view != 41 { return 2 }
    }
    {
        let guard = cell.borrow_mut()
        match unsafe { cell.try_borrow_unguarded() } {
            success(_) => { return 3 },
            failure(_) => {}
        }
        core.mem.drop(guard)
    }
    {
        let guard = cell.borrow()
        match unsafe { cell.try_borrow_unguarded() } {
            success(value) => { if *value != 41 { return 4 } },
            failure(_) => { return 5 }
        }
        core.mem.drop(guard)
    }
    match cell.try_borrow_mut() {
        success(_) => {},
        failure(_) => { return 6 }
    }
    let counter = unsafe { core.ptr.from_ref(cell) as ptr<mut isize> }
    unsafe {
        *counter = isize.MAX
        match cell.try_borrow_unguarded() {
            success(value) => { if *value != 41 { return 7 } },
            failure(_) => { return 8 }
        }
        if *counter != isize.MAX { return 9 }
        *counter = 0isize
    }
    let array = core.cell.RefCell.new([3i32, 7, 11])
    let unsized: read core.cell.RefCell<[i32]> = read array
    match unsafe { unsized.try_borrow_unguarded() } {
        success(value) => {
            if value.len() != 3usize || value[2] != 11 { return 10 }
        },
        failure(_) => { return 11 }
    }
    0
}
