import alloc.alloc.{Allocator, Layout, AllocError, Global};
import alloc.vec.Vec;

// Allocator that fails once the shared budget of successful allocations runs out.
copy type Limited { budget: ptr<mut i32>; live: ptr<mut i32> }

extend Limited implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 { throw AllocError(layout.size(), layout.align()) }
        unsafe { *self.budget -= 1 }
        unsafe { *self.live += 1 }
        let mut_global = Global()
        var g = mut_global
        try g.allocate(layout)
    }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe { *self.live -= 1 }
        var g = Global()
        g.deallocate(p, layout)
    }
    mut fn grow(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        if unsafe { *self.budget } <= 0 { throw AllocError(new_size, old.align()) }
        unsafe { *self.budget -= 1 }
        var g = Global()
        try g.grow(p, old, new_size)
    }
    mut fn shrink(p: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var g = Global()
        try g.shrink(p, old, new_size)
    }
}

fn main(): i32 {
    var budget = 3
    var live = 0
    let a = Limited(core.ptr.from_mut(budget), core.ptr.from_mut(live))
    {
        var v = alloc.vec.new_in<i32, Limited>(a)
        var i = 0
        var failed = 0
        while i < 1000 {
            match capture v.try_push(i + 0) {
                success(_) => {},
                failure(_) => { failed += 1; break }
            }
            i += 1
        }
        if failed != 1 || v.len() == 0usize { return 1 }
        let kept = v.len()
        match capture v.try_reserve(1000000usize) { success(_) => { return 2 }, failure(_) => {} }
        if v.len() != kept { return 3 }
        var j = 0usize
        while j < kept { if v[j] != (j as i32) { return 4 }; j += 1usize }
    }
    if live != 1 && live != 0 { return 5 }

    var budget2 = 0
    var live2 = 0
    let b = Limited(core.ptr.from_mut(budget2), core.ptr.from_mut(live2))
    match capture alloc.boxed.try_new_in(5, b) {
        success(_) => { return 6 },
        failure(_) => {}
    }
    var m = alloc.hash_map.new_in<i32, i32, Limited>(Limited(core.ptr.from_mut(budget2), core.ptr.from_mut(live2)))
    match capture m.try_insert(1, 2) { success(_) => { return 7 }, failure(_) => {} }
    if m.len() != 0usize { return 8 }
    0
}
