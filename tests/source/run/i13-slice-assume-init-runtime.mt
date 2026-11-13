// profiles: debug release
import core.mem

fn main(): i32 {
    var storage = [
        core.mem.MaybeUninit<i32>.new(1i32),
        core.mem.MaybeUninit<i32>.new(2i32),
        core.mem.MaybeUninit<i32>.new(99i32)
    ]
    let slots: mut [core.mem.MaybeUninit<i32>] = mut storage
    {
        let written = slots.write_copy_of_slice(read [4i32, 7i32])
        written[0usize] += 1
        if written.len() != 2usize { return 1 }
    }
    {
        let initialized = unsafe { slots.assume_init_mut() }
        initialized[1usize] += 1
    }
    let initialized = unsafe { slots.assume_init_ref() }
    if initialized[0usize] != 5 || initialized[1usize] != 8 || initialized[2usize] != 99 { return 2 }
    0
}
