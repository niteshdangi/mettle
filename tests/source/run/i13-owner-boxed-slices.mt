import alloc.boxed

type DropItem {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    let written = boxed.new_uninit<i32>().write(37)
    if *written.get() != 37 { return 5 }

    var drops = 0
    {
        var uninit = boxed.new_uninit_slice<DropItem>(3usize)
        {
            let slots = uninit.get_mut()
            let _ = slots[0usize].write(DropItem(core.ptr.from_mut(drops), 11))
            let _ = slots[1usize].write(DropItem(core.ptr.from_mut(drops), 22))
            let _ = slots[2usize].write(DropItem(core.ptr.from_mut(drops), 33))
        }
        let initialized = unsafe { uninit.assume_init() }
        if initialized.get().len() != 3usize ||
            initialized.get()[0usize].value != 11 ||
            initialized.get()[2usize].value != 33 {
            return 1
        }
    }
    if drops != 3 { return 2 }

    let zeroed = boxed.new_zeroed_slice<u32>(4usize)
    let initialized_zeroed = unsafe { zeroed.assume_init() }
    if initialized_zeroed.get().len() != 4usize ||
        initialized_zeroed.get()[0usize] != 0u32 ||
        initialized_zeroed.get()[3usize] != 0u32 {
        return 3
    }

    let empty = boxed.new_uninit_slice<i32>(0usize)
    if empty.get().len() != 0usize { return 4 }
    0
}
