import alloc.alloc.{Allocator, Global, Layout, AllocError, layout_of, layout_unchecked}

extern "C" {
    unsafe fn mettle_c_heap_global_begin(): Unit;
    unsafe fn mettle_c_heap_global_end(): usize;
}

type Counts { allocations: usize; releases: usize }
copy type Counting { state: ptr<mut Counts> }

unsafe extend Counting implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        if layout.size() != 0usize { unsafe { (*self.state).allocations += 1usize } }
        pointer
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        global.deallocate(pointer, layout)
        if layout.size() != 0usize { (*self.state).releases += 1usize }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.grow(pointer, old, size)
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.shrink(pointer, old, size)
    }
}

fn main(): i32 {
    var global = Global()
    let layout = layout_of<u64>()
    unsafe { mettle_c_heap_global_begin() }
    let pointer = match capture global.allocate(layout) {
        success(value) => value,
        failure(_) => {
            let _calls = unsafe { mettle_c_heap_global_end() }
            return 1
        }
    }
    let grown = match unsafe { capture global.grow(pointer, layout, 16usize) } {
        success(value) => value,
        failure(_) => {
            let _calls = unsafe { mettle_c_heap_global_end() }
            unsafe { global.deallocate(pointer, layout) }
            return 2
        }
    }
    let control = unsafe { mettle_c_heap_global_end() }
    unsafe { global.deallocate(grown, layout_unchecked(16usize, layout.align())) }
    if control != 2usize { return 3 }

    var counts = Counts(0usize, 0usize)
    let state = core.ptr.from_mut(counts)
    {
        var values = alloc.binary_heap.with_capacity_in<i32, Counting>(3usize, Counting(state))
        values.push(2)
        values.push(5)
        values.push(3)
        let pointer = values.as_slice().as_ptr()
        let capacity = values.capacity()
        if counts.allocations != 1usize || counts.releases != 0usize { return 4 }
        unsafe { mettle_c_heap_global_begin() }
        let sorted = values.into_sorted_vec()
        let global_calls = unsafe { mettle_c_heap_global_end() }
        if global_calls != 0usize { return 5 }
        if sorted.len() != 3usize || sorted[0usize] != 2 ||
            sorted[1usize] != 3 || sorted[2usize] != 5 { return 6 }
        if sorted.as_ptr() != pointer || sorted.capacity() != capacity ||
            sorted.allocator().state != state { return 7 }
        if counts.allocations != 1usize || counts.releases != 0usize { return 8 }
    }
    if counts.allocations != 1usize || counts.releases != 1usize { return 9 }
    0
}
