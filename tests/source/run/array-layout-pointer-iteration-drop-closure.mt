// flags: --sanitize address

static mut DROPS: usize = 0usize

type Item {
    value: i32
    drop { unsafe { DROPS += 1usize } }
}

fn main(): i32 {
    unsafe { DROPS = 0usize }
    {
        let values = [Item(10), Item(20), Item(12)]
        let pointer = core.ptr.from_ref(values).cast<Item>()
        let end = unsafe { pointer.add(3usize) }
        let distance = unsafe { end.offset_from(pointer) }
        let aligned = pointer.addr() % core.mem.align_of<Item>() == 0usize
        var sum = 0
        var visited = 0usize
        for item in read values {
            sum += item.value
            visited += 1usize
        }

        let empty: [Item; 0usize] = []
        let empty_pointer = core.ptr.from_ref(empty).cast<Item>()
        let empty_end = unsafe { empty_pointer.add(0usize) }
        if core.mem.size_of<[Item; 0usize]>() != 0usize ||
           core.mem.align_of<[Item; 0usize]>() != core.mem.align_of<Item>() ||
           unsafe { empty_end.offset_from(empty_pointer) } != 0isize {
            return 1
        }
        if core.mem.size_of<[Item; 3usize]>() !=
               3usize * core.mem.size_of<Item>() ||
           !aligned || distance != 3isize || visited != 3usize || sum != 42 {
            return 2
        }
        unsafe {
            if DROPS != 0usize { return 3 }
        }
    }
    unsafe {
        if DROPS != 3usize { return 4 }
    }
    0
}
