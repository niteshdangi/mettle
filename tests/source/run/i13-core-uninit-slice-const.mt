// profiles: debug release
import core.mem
import core.cmp.PartialEq

const fn initialize(): [i32; 3] {
    var storage = [
        core.mem.MaybeUninit<i32>.new(1i32),
        core.mem.MaybeUninit<i32>.new(2i32),
        core.mem.MaybeUninit<i32>.new(99i32)
    ]
    let slots: mut [core.mem.MaybeUninit<i32>] = mut storage
    {
        let written = slots.write_copy_of_slice(read [4i32, 7i32])
        written[0usize] += 1
        if written.len() != 2usize { panic("wrong initialized extent") }
    }
    {
        let initialized = unsafe { slots.assume_init_mut() }
        initialized[1usize] += 1
    }
    let initialized = unsafe { slots.assume_init_ref() }
    [initialized[0usize], initialized[1usize], initialized[2usize]]
}

const VALUES: [i32; 3] = initialize()

const fn empty(): usize {
    var storage: [core.mem.MaybeUninit<i32>; 0] = []
    let slots: mut [core.mem.MaybeUninit<i32>] = mut storage
    let nothing: [i32; 0] = []
    slots.write_copy_of_slice(read nothing).len()
}

const EMPTY: usize = empty()

fn main(): i32 {
    if VALUES != [5i32, 8i32, 99i32] || EMPTY != 0usize { return 1 }
    0
}
