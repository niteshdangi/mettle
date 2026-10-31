import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.arc
import alloc.rc
import core.default.Default

type NonCloneAllocator {}

extend NonCloneAllocator implements Default {
    static fn default(): NonCloneAllocator { NonCloneAllocator() }
}

extend NonCloneAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.allocate(layout)
    }
    mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        global.deallocate(pointer, layout)
    }
    mut fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.grow(pointer, old, new_size)
    }
    mut fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.shrink(pointer, old, new_size)
    }
}

fn main(): i32 {
    let local = rc.Rc<i32, NonCloneAllocator>.(Default).default()
    let shared = arc.Arc<i32, NonCloneAllocator>.(Default).default()
    if *local.get() != 0 || *shared.get() != 0 { return 1 }
    0
}
