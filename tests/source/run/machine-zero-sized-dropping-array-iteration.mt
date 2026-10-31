static mut DROPS: usize = 0usize

type Empty {
    drop { unsafe { DROPS += 1usize } }
}

fn main(): i32 {
    unsafe { DROPS = 0usize }
    if core.mem.size_of<Empty>() != 0usize ||
        core.mem.align_of<Empty>() != 1usize {
        return 1
    }
    {
        let values = [Empty(), Empty(), Empty()]
        var visited = 0usize
        for value in read values { visited += 1usize }
        if visited != 3usize { return 2 }
    }
    unsafe {
        if DROPS != 3usize { return 3 }
    }
    0
}
