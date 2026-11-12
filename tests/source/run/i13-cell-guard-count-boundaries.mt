// profiles: debug release

import core.cell
import std.panic.{catch_panic, CatchResult}

fn shared_split<region r>(
    read value: [i32; 2] from r
): (read i32 from r, read i32 from r) {
    (read value[0], read value[1])
}
fn exclusive_split<region r>(
    mut value: [i32; 2] from r
): (mut [i32] from r, mut [i32] from r) {
    value.split_at_mut(1usize)
}
fn main(): i32 {
    let cell = core.cell.RefCell.new([1i32, 2])
    let counter = unsafe { core.ptr.from_ref(cell) as ptr<mut isize> }
    let shared_result = catch_panic(fn(): Unit {
        let original = cell.borrow()
        unsafe { *counter = isize.MAX }
        let _ = core.cell.Ref<[i32; 2]>.map_split(original, shared_split)
    })
    match shared_result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    unsafe {
        if *counter != isize.MAX - 1isize { return 2 }
        *counter = 0isize
    }
    let exclusive_result = catch_panic(fn(): Unit {
        let original = cell.borrow_mut()
        unsafe { *counter = isize.MIN }
        let _ = core.cell.RefMut<[i32; 2]>.map_split(original, exclusive_split)
    })
    match exclusive_result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    unsafe {
        if *counter != isize.MIN + 1isize { return 4 }
        *counter = 0isize
    }
    {
        let original = cell.borrow()
        unsafe { *counter = isize.MAX }
        let cloned = catch_panic(fn(): Unit {
            let _ = original.clone()
        })
        match cloned {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 5 }
        }
        unsafe {
            if *counter != isize.MAX { return 6 }
            *counter = 1isize
        }
    }
    unsafe { if *counter != 0isize { return 7 } }
    {
        let (first, last) = core.cell.Ref<[i32; 2]>.map_split(
            cell.borrow(), shared_split)
        core.mem.forget(last)
        core.mem.drop(first)
    }
    unsafe { if *counter != 1isize { return 8 } }
    match cell.try_borrow_mut() {
        success(_) => { return 9 },
        failure(_) => {}
    }
    0
}
