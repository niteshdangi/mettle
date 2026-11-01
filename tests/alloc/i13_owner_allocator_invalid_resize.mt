import alloc.alloc.{ Allocator, Global, AllocError, layout_from_size_align }

fn check(): i32 throws AllocError {
    let layout = match capture layout_from_size_align(8usize, 8usize) {
        success(value) => value,
        failure(_) => { return 10 }
    }
    var global = Global()
    let pointer = try global.allocate(layout)
    unsafe { core.ptr.write(pointer, 0x5Au8) }

    let oversized = 0x8000000000000000usize
    match capture global.grow(pointer, layout, oversized) {
        success(_) => { return 1 },
        failure(error) => {
            if error.size != oversized || error.align != 8usize { return 2 }
        }
    }
    if unsafe { core.ptr.`read`(pointer) } != 0x5Au8 { return 3 }

    match capture global.shrink(pointer, layout, oversized) {
        success(_) => { return 4 },
        failure(error) => {
            if error.size != oversized || error.align != 8usize {
                return 5
            }
        }
    }
    if unsafe { core.ptr.`read`(pointer) } != 0x5Au8 { return 6 }

    global.deallocate(pointer, layout)
    0
}

fn main(): i32 {
    match capture check() {
        success(result) => result,
        failure(_) => 11
    }
}
