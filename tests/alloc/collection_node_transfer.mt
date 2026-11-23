import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.btree
import alloc.linked_list

copy type Tracked {
    counts: ptr<mut [i32; 2]>
    cloned: ptr<mut [i32; 2]>
}

extend Tracked implements core.clone.Clone {
    fn clone(): Tracked { Tracked(self.cloned, self.cloned) }
}

unsafe extend Tracked implements Allocator {
    fn is_compatible(read other: Tracked): bool { self.counts == other.counts }
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe { (*self.counts)[0usize] += 1 }
        pointer
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe { (*self.counts)[1usize] += 1 }
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.grow(pointer, old, size) }
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        var global = Global()
        unsafe { try global.shrink(pointer, old, size) }
    }
}

fn main(): i32 {
    var counts = [0; 2]
    let counter = core.ptr.from_mut(counts)
    var at = 0usize
    while at <= 32usize {
        {
            var list = linked_list.new_in<i32, Tracked>(Tracked(counter, counter))
            var i = 0
            while i < 32 { list.push_back(i + 0); i += 1 }
            let allocations = counts[0usize]
            let first = core.ptr.from_ref(*list.front().or_panic())
            var upper = list.split_off(at)
            if list.len() != at || upper.len() != 32usize - at ||
                counts[0usize] != allocations { return 1 }
            if at == 0usize {
                if core.ptr.from_ref(*upper.front().or_panic()) != first { return 2 }
            }
            if at != 0usize && list.pop_back() != present(at as i32 - 1) { return 3 }
            if at != 32usize && upper.pop_back() != present(31) { return 3 }
            var expected = at as i32
            while upper.len() != 0usize {
                if upper.pop_front() != present(expected) { return 3 }
                expected += 1
            }
            if expected != (if at == 32usize { 32 } else { 31 }) { return 4 }
        }
        at += 1usize
    }
    if counts[0usize] != counts[1usize] { return 5 }

    var original = [0; 2]
    var cloned = [0; 2]
    let original_counts = core.ptr.from_mut(original)
    let cloned_counts = core.ptr.from_mut(cloned)
    {
        var list = linked_list.new_in<i32, Tracked>(Tracked(original_counts, cloned_counts))
        var i = 0
        while i < 16 { list.push_back(i + 0); i += 1 }
        var upper = list.split_off(8usize)
        if list.len() != 8usize || upper.len() != 8usize ||
            original[1usize] != 8 || cloned[0usize] != 8 { return 6 }
        if upper.pop_back() != present(15) || list.pop_back() != present(7) { return 7 }
    }
    if original[0usize] != original[1usize] || cloned[0usize] != cloned[1usize] { return 8 }
    {
        var map = btree.new_in<i32, i32, Tracked>(Tracked(counter, counter))
        var i = 0
        while i < 1000 { let _ = map.insert(i + 0, i + 0); i += 1 }
        let allocations = counts[0usize]
        let first = core.ptr.from_ref(*map.get(0).or_panic())
        var upper = map.split_off(0)
        if !map.is_empty() || upper.len() != 1000usize ||
            counts[0usize] != allocations ||
            core.ptr.from_ref(*upper.get(0).or_panic()) != first { return 9 }
        map.append(mut upper)
        if map.len() != 1000usize || !upper.is_empty() ||
            counts[0usize] != allocations ||
            core.ptr.from_ref(*map.get(0).or_panic()) != first { return 10 }
        let empty = map.split_off(1000)
        if !empty.is_empty() || map.len() != 1000usize ||
            counts[0usize] != allocations { return 11 }
    }
    if counts[0usize] != counts[1usize] { return 12 }
    {
        var map = btree.new_in<i32, i32, Tracked>(Tracked(original_counts, cloned_counts))
        var i = 0
        while i < 128 { let _ = map.insert(i + 0, i + 0); i += 1 }
        let allocations = cloned[0usize]
        var upper = map.split_off(0)
        if map.len() != 0usize || upper.len() != 128usize ||
            cloned[0usize] <= allocations { return 13 }
        map.append(mut upper)
        if map.len() != 128usize || !upper.is_empty() { return 14 }
    }
    if original[0usize] != original[1usize] || cloned[0usize] != cloned[1usize] { return 15 }
    0
}
