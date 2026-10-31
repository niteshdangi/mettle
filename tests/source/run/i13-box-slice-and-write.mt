import alloc.boxed

type Counted {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter += 1 } }
}

fn main(): i32 {
    var drops = 0
    {
        let owned = boxed.Box<Counted>.new(Counted(core.ptr.from_mut(drops)))
        let value = owned.into_inner()
        if drops != 0 { return 1 }
        let _kept = value
    }
    if drops != 1 { return 2 }

    var slot = boxed.Box<i32>.new_uninit()
    {
        let written = slot.write(7)
        if written != 7 { return 3 }
    }
    let initialized = unsafe { slot.assume_init() }
    if initialized.get() != 7 { return 4 }

    var uninit = boxed.new_uninit_slice<i32>(2usize)
    if uninit.get().len() != 2usize { return 5 }
    {
        let _first = uninit.get_mut()[0usize].write(4)
    }
    {
        let _second = uninit.get_mut()[1usize].write(5)
    }
    let ready = unsafe { uninit.get().assume_init_ref() }
    if ready[0usize] != 4 || ready[1usize] != 5 { return 6 }

    let zeroed = boxed.Box<i32>.new_zeroed_slice(3usize)
    if zeroed.get().len() != 3usize { return 7 }
    let zeros = unsafe { zeroed.get().assume_init_ref() }
    if zeros[0usize] != 0 || zeros[1usize] != 0 || zeros[2usize] != 0 { return 8 }

    let empty = boxed.new_uninit_slice<i32>(0usize)
    if empty.get().len() != 0usize { return 9 }

    var through = boxed.Box<i32>.new(1)
    let shared = through.as_ptr()
    unsafe { core.ptr.write(through.as_mut_ptr(), 9) }
    if through.get() != 9 { return 10 }
    if shared != through.as_ptr() { return 11 }
    0
}
