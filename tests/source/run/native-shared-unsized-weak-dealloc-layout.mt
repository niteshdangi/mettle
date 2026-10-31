import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.arc.Arc
import package.core.clone.Clone

type Tracker {
    size: ptr<mut usize>
    align: ptr<mut usize>
    frees: ptr<mut i32>
    mismatches: ptr<mut i32>
}

extend Tracker implements Clone {
    fn clone(): Tracker {
        Tracker(self.size, self.align, self.frees, self.mismatches)
    }
}

extend Tracker implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            *self.size = layout.size()
            *self.align = layout.align()
        }
        var global = Global()
        try global.allocate(layout)
    }
    mut fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if layout.size() != *self.size || layout.align() != *self.align {
                *self.mismatches += 1
            }
            *self.frees += 1
        }
        var global = Global()
        global.deallocate(p, layout)
    }
    mut fn grow(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.grow(p, old, size)
    }
    mut fn shrink(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.shrink(p, old, size)
    }
}

fn main(): i32 {
    var size = 0usize
    var align = 0usize
    var frees = 0
    var mismatches = 0
    let tracker = Tracker(
        core.ptr.from_mut(size),
        core.ptr.from_mut(align),
        core.ptr.from_mut(frees),
        core.ptr.from_mut(mismatches)
    )
    let weak: alloc.arc.Weak<[i32], Tracker> = {
        let sized = alloc.arc.new_in([1, 2, 3], tracker)
        let owner: Arc<[i32], Tracker> = sized
        weak owner
    }
    if frees != 0 { return 1 }
    {
        let last = weak
        if last.strong_count() != 0usize { return 2 }
    }
    if frees == 1 && mismatches == 0 && size != 0usize && align != 0usize {
        0
    } else {
        3
    }
}
