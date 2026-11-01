import alloc.arc
import alloc.rc

// The counters outlive the slices and are mutated only during element drops.
type DropItem {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var local_drops = 0
    {
        var uninit = rc.new_uninit_slice<DropItem>(2usize)
        {
            match take uninit.get_mut() {
                present(slots) => {
                    let _ = slots[0usize].write(DropItem(core.ptr.from_mut(local_drops), 13))
                    let _ = slots[1usize].write(DropItem(core.ptr.from_mut(local_drops), 17))
                },
                none => { return 10 }
            }
        }
        let initialized = unsafe { uninit.assume_init() }
        if initialized.get().len() != 2usize ||
            initialized.get()[1usize].value != 17 {
            return 1
        }
        let observer = initialized.downgrade()
        match observer.upgrade() {
            present(owner) => {
                if owner.get().len() != 2usize || owner.get()[0usize].value != 13 {
                    return 2
                }
            },
            none => { return 3 }
        }
    }
    if local_drops != 2 { return 4 }

    var atomic_drops = 0
    {
        var uninit = arc.new_uninit_slice<DropItem>(2usize)
        {
            match take uninit.get_mut() {
                present(slots) => {
                    let _ = slots[0usize].write(DropItem(core.ptr.from_mut(atomic_drops), 23))
                    let _ = slots[1usize].write(DropItem(core.ptr.from_mut(atomic_drops), 29))
                },
                none => { return 11 }
            }
        }
        let initialized = unsafe { uninit.assume_init() }
        if initialized.get().len() != 2usize ||
            initialized.get()[1usize].value != 29 {
            return 5
        }
        let observer = initialized.downgrade()
        match observer.upgrade() {
            present(owner) => {
                if owner.get().len() != 2usize || owner.get()[0usize].value != 23 {
                    return 6
                }
            },
            none => { return 7 }
        }
    }
    if atomic_drops != 2 { return 8 }

    let local_zeroed = unsafe { rc.new_zeroed_slice<u32>(2usize).assume_init() }
    let atomic_zeroed = unsafe { arc.new_zeroed_slice<u32>(2usize).assume_init() }
    if local_zeroed.get().len() != 2usize ||
        local_zeroed.get()[1usize] != 0u32 ||
        atomic_zeroed.get().len() != 2usize ||
        atomic_zeroed.get()[1usize] != 0u32 {
        return 9
    }
    0
}
