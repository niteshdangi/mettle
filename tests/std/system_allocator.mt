import std.alloc.{GlobalAlloc, Layout, System}

fn run(): i32 throws std.alloc.LayoutError {
    let layout = try Layout.from_size_align(8usize, 8usize)
    var allocator = System()
    let pointer = unsafe { allocator.alloc(layout) }
    if pointer == core.ptr.null_mut<u8>() { return 1 }
    unsafe { pointer.write(37u8) }
    if unsafe { *pointer } != 37u8 {
        unsafe { allocator.dealloc(pointer, layout) }
        return 2
    }
    unsafe { allocator.dealloc(pointer, layout) }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
