import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.btree
import alloc.linked_list
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}

type StoredKey {
    value: i32
    identity: i32
    drops: ptr<mut [i32; 2]>
    drop { unsafe { (*self.drops)[self.identity as usize] += 1 } }
}

extend StoredKey implements PartialEq {
    fn eq(read other: StoredKey): bool { self.value == other.value }
}
extend StoredKey implements Eq {}
extend StoredKey implements PartialOrd {
    fn partial_cmp(read other: StoredKey): Ordering? { present(self.cmp(other)) }
}
extend StoredKey implements Ord {
    fn cmp(read other: StoredKey): Ordering { self.value.cmp(other.value) }
}

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
    var mode = 0
    while mode < 5 {
        {
            var left = btree.new_in<i32, i32, Tracked>(Tracked(counter, counter))
            var right = btree.new_in<i32, i32, Tracked>(Tracked(counter, counter))
            var i = 0
            while i < 1000 {
                let l = if mode == 1 { i + 1000 } else if mode == 2 { i * 2 } else { i + 0 }
                let r = if mode == 0 { i + 1000 } else if mode == 2 { i * 2 + 1 } else if mode == 3 { i + 500 } else { i + 0 }
                let _ = left.insert(l + 0, l)
                let _ = right.insert(r + 0, -r - 1)
                i += 1
            }
            let allocations = counts[0usize]
            left.append(mut right)
            let expected = if mode == 3 { 1500usize } else if mode == 4 { 1000usize } else { 2000usize }
            if left.len() != expected || !right.is_empty() || counts[0usize] != allocations { return 16 }
            i = 0
            while i < expected as i32 {
                let donor = if mode == 0 { i >= 1000 } else if mode == 1 { i < 1000 } else if mode == 2 { i % 2 == 1 } else if mode == 3 { i >= 500 } else { true }
                if left.pop_first() != present((i + 0, if donor { -i - 1 } else { i + 0 })) { return 17 }
                i += 1
            }
        }
        if counts[0usize] != counts[1usize] { return 18 }
        mode += 1
    }
    var size = 1
    while size <= 150 {
        var left = btree.new<i32, i32>()
        var right = btree.new<i32, i32>()
        var i = 0
        while i < size {
            let _ = left.insert(i * 2, i * 2)
            let _ = right.insert(i * 2 + 1, i * 2 + 1)
            i += 1
        }
        left.append(mut right)
        if left.len() != (size * 2) as usize || !right.is_empty() { return 19 }
        let _ = left.insert(size * 2, size * 2)
        i = size * 2
        while i >= 0 {
            if left.pop_last() != present((i + 0, i + 0)) { return 20 }
            i -= 1
        }
        size += 1
    }
    var key_drops = [0; 2]
    let keys = core.ptr.from_mut(key_drops)
    {
        var left = btree.new<StoredKey, i32>()
        var right = btree.new<StoredKey, i32>()
        var i = 0
        while i < 100 {
            let _ = left.insert(StoredKey(i + 0, 0, keys), i + 0)
            let _ = right.insert(StoredKey(i + 0, 1, keys), -i - 1)
            i += 1
        }
        left.append(mut right)
        if !right.is_empty() || left.len() != 100usize || key_drops != [0, 100] { return 21 }
        i = 0
        for entry in read left {
            if entry.key.identity != 0 || entry.key.value != i || entry.value != -i - 1 { return 22 }
            i += 1
        }
    }
    if key_drops != [100, 100] { return 23 }
    {
        var left = btree.new_in<i32, i32, Tracked>(Tracked(original_counts, original_counts))
        var right = btree.new_in<i32, i32, Tracked>(Tracked(cloned_counts, cloned_counts))
        let _ = left.insert(-1, -1)
        var i = 0
        while i < 128 { let _ = right.insert(i + 0, i + 0); i += 1 }
        let allocations = original[0usize]
        left.append(mut right)
        if left.len() != 129usize || !right.is_empty() || original[0usize] <= allocations { return 24 }
        i = -1
        while i < 128 {
            if left.pop_first() != present((i + 0, i + 0)) { return 25 }
            i += 1
        }
    }
    if original[0usize] != original[1usize] || cloned[0usize] != cloned[1usize] { return 26 }
    0
}
