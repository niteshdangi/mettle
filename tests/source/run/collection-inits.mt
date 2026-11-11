import alloc.alloc.{Allocator, Layout, AllocError, Global}
import alloc.vec.List
import alloc.hash_map.{Map, Set}
import alloc.string.String

type Arena {
    allocations: ptr<mut i32>
    frees: ptr<mut i32>
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

unsafe extend Arena implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let p = try global.allocate(layout)
        unsafe { *self.allocations += 1 }
        p
    }
    mut unsafe fn deallocate(p: ptr<mut u8>, layout: Layout): Unit {
        unsafe { *self.frees += 1 }
        var global = Global()
        unsafe { global.deallocate(p, layout) }
    }
    mut unsafe fn grow(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.grow(p, old, size) }
    }
    mut unsafe fn shrink(p: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.shrink(p, old, size) }
    }
}

fn main(): i32 {
    let empty = List<i32>()
    let map = Map<i32, i32>()
    let map_in = Map<i32, i32, Global>(allocator: Global())
    let set = Set<i32>()
    let set_in = Set<i32, Global>(allocator: Global())
    let text = String("ok")
    let other = String("ok", allocator: Global())
    if empty.len() + map.len() + map_in.len() + set.len() + set_in.len() != 0usize { return 4 }
    if text.as_text() != "ok" || other.as_text() != "ok" { return 5 }
    var allocations = 0
    var frees = 0
    var drops = 0
    {
        let arena = Arena(core.ptr.from_mut(allocations), core.ptr.from_mut(frees), core.ptr.from_mut(drops))
        var xs = List<i32, Arena>(allocator: take arena)
        xs.push(42)
        if xs[0usize] != 42 { return 1 }
    }
    {
        let arena = Arena(core.ptr.from_mut(allocations), core.ptr.from_mut(frees), core.ptr.from_mut(drops))
        var xs = List<i32>(allocator: take arena)
        xs.push(7)
        if xs[0usize] != 7 { return 2 }
    }
    if allocations == 2 && frees == 2 && drops == 2 { 0 } else { 3 }
}
