// profiles: debug release
import core.mem
import core.clone.Clone
import std.panic.{catch_panic, CatchResult}

static mut DROPS: usize = 0usize
static mut CLONES: usize = 0usize
type Item {
    value: i32
    drop { unsafe { DROPS += 1usize } }
}
extend Item implements Clone {
    fn clone(): Item {
        unsafe {
            CLONES += 1usize
            if CLONES == 2usize { panic("clone stopped") }
        }
        Item(self.value)
    }
}

type DropBomb {
    count: ptr<mut usize>
    fail: bool
    drop {
        unsafe { *self.count += 1usize }
        if self.fail { panic("drop stopped") }
    }
}

fn main(): i32 {
    {
        let source = [Item(3), Item(4), Item(5)]
        var storage = [
            core.mem.MaybeUninit<Item>.uninit(),
            core.mem.MaybeUninit<Item>.uninit(),
            core.mem.MaybeUninit<Item>.uninit()
        ]
        let stopped = catch_panic(fn(): Unit {
            let slots: mut [core.mem.MaybeUninit<Item>] = mut storage
            let _ = slots.write_clone_of_slice(read source)
        })
        match stopped {
            CatchResult.Panicked(info) => {
                if info.message() != "clone stopped" { return 1 }
            },
            CatchResult.Returned(_) => { return 2 }
        }
        if unsafe { DROPS != 1usize || CLONES != 2usize } { return 3 }
        unsafe { CLONES = 10usize }
        {
            let slots: mut [core.mem.MaybeUninit<Item>] = mut storage
            let written = slots.write_clone_of_slice(read source)
            if written.len() != 3usize || written[2usize].value != 5 { return 4 }
        }
        let slots: mut [core.mem.MaybeUninit<Item>] = mut storage
        unsafe { slots.assume_init_drop() }
        if unsafe { DROPS != 4usize } { return 5 }
    }
    if unsafe { DROPS != 7usize } { return 6 }
    var short = [core.mem.MaybeUninit<i32>.new(99i32)]
    let stopped = catch_panic(fn(): Unit {
        let slots: mut [core.mem.MaybeUninit<i32>] = mut short
        let _ = slots.write_copy_of_slice(read [1i32, 2i32])
    })
    match stopped {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if unsafe { short[0usize].assume_init_read() } != 99 { return 8 }
    var empty: [core.mem.MaybeUninit<Item>; 0] = []
    let slots: mut [core.mem.MaybeUninit<Item>] = mut empty
    let source: [Item; 0] = []
    if slots.write_clone_of_slice(read source).len() != 0usize { return 9 }
    unsafe { slots.assume_init_drop() }
    if unsafe { DROPS != 7usize } { return 10 }
    var drop_count = 0usize
    let counter = core.ptr.from_mut(drop_count)
    let dropped = catch_panic(fn(): Unit {
        var storage = [
            core.mem.MaybeUninit<DropBomb>.new(DropBomb(counter, false)),
            core.mem.MaybeUninit<DropBomb>.new(DropBomb(counter, true)),
            core.mem.MaybeUninit<DropBomb>.new(DropBomb(counter, false))
        ]
        let slots: mut [core.mem.MaybeUninit<DropBomb>] = mut storage
        unsafe { slots.assume_init_drop() }
    })
    match dropped {
        CatchResult.Panicked(info) => {
            if info.message() != "drop stopped" { return 11 }
        },
        CatchResult.Returned(_) => { return 12 }
    }
    if drop_count != 3usize { return 13 }
    0
}
