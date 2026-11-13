import alloc.alloc.{Allocator, Global, Layout, AllocError}
import core.cmp.{PartialEq, Eq}
import core.hash.{Hash, Hasher}

type AllocationState { grows: usize; shrinks: usize; fail_shrink: bool; fail_grow: bool }
type CountingAllocator { state: ptr<mut AllocationState> }
unsafe extend CountingAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        try global.allocate(layout)
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.state).grows += 1usize
            if (*self.state).fail_grow { throw AllocError(size, old.align()) }
        }
        var global = Global()
        unsafe { try global.grow(pointer, old, size) }
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.state).shrinks += 1usize
            if (*self.state).fail_shrink { throw AllocError(size, old.align()) }
        }
        var global = Global()
        unsafe { try global.shrink(pointer, old, size) }
    }
}

type Key { value: i32; hashes: ptr<mut usize> }
extend Key implements PartialEq {
    fn eq(read other: Key): bool { self.value == other.value }
}
extend Key implements Eq {}
extend Key implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        unsafe { *self.hashes += 1usize }
        state.write_i32(self.value)
    }
}

copy type InteriorKey { value: ptr<mut i32> }
extend InteriorKey implements PartialEq {
    fn eq(read other: InteriorKey): bool { unsafe { *self.value == *other.value } }
}
extend InteriorKey implements Eq {}
extend InteriorKey implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit { state.write_i32(unsafe { *self.value }) }
}

type DropValue {
    count: ptr<mut usize>
    drop { unsafe { *self.count += 1usize } }
}

fn main(): i32 {
    var allocation = AllocationState(0usize, 0usize, false, false)
    var map = alloc.hash_map.new_in<i32, i32, CountingAllocator>(
        CountingAllocator(core.ptr.from_mut(allocation)))
    map.reserve(32usize)
    let _ = map.insert(1, 10)
    let _ = map.insert(2, 20)
    allocation.grows = 0usize
    map.shrink_to(8usize)
    if allocation.grows != 0usize || allocation.shrinks != 1usize ||
        map.capacity() < 8usize { return 1 }
    map.reserve(32usize)
    let old_capacity = map.capacity()
    allocation.fail_shrink = true
    allocation.grows = 0usize
    map.shrink_to(8usize)
    if allocation.grows != 0usize || map.capacity() < 8usize ||
        map.capacity() > old_capacity || *map.get(1).or_panic() != 10 ||
        *map.get(2).or_panic() != 20 { return 2 }

    var hashes = 0usize
    let counter = core.ptr.from_mut(hashes)
    var entries = alloc.hash_map.new<Key, i32>()
    *entries.or_insert(Key(1, counter), 10) += 1
    if hashes != 1usize || entries.len() != 1usize { return 3 }
    hashes = 0usize
    if *entries.or_insert(Key(1, counter), 99) != 11 ||
        hashes != 1usize || entries.len() != 1usize { return 4 }
    entries.reserve(32usize)
    hashes = 0usize
    if *entries.or_insert(Key(2, counter), 20) != 20 ||
        hashes != 1usize || entries.len() != 2usize { return 5 }

    var left = alloc.hash_map.set_new<Key>()
    var right = alloc.hash_map.set_new<Key>()
    let _ = left.insert(Key(1, counter))
    let _ = left.insert(Key(2, counter))
    let _ = right.insert(Key(2, counter))
    let _ = right.insert(Key(3, counter))
    hashes = 0usize
    {
        var combined = left.`union`(read right)
        let first = combined.next().or_panic().value
        let second = combined.next().or_panic().value
        if first + second != 3 || hashes != 0usize { return 6 }
        if combined.next().or_panic().value != 3 || combined.next().is_present() ||
            hashes != 2usize { return 7 }
    }
    hashes = 0usize
    {
        var difference = left.difference(read right)
        if difference.next().or_panic().value != 1 || difference.next().is_present() ||
            difference.next().is_present() || hashes != 2usize { return 8 }
    }
    var first_key = 1
    var second_key = 2
    var query = 3
    var interior = alloc.hash_map.new<InteriorKey, i32>()
    let _ = interior.insert(InteriorKey(core.ptr.from_mut(first_key)), 10)
    let _ = interior.insert(InteriorKey(core.ptr.from_mut(second_key)), 20)
    {
        let vacant = interior.entry(InteriorKey(core.ptr.from_mut(query)))
        query = 1
        let value = vacant.or_insert(99)
        if *value != 10 { return 9 }
    }
    if interior.len() != 2usize { return 10 }
    var dropped = 0usize
    var retained = 0usize
    {
        var failing = alloc.hash_map.new_in<i32, DropValue, CountingAllocator>(
            CountingAllocator(core.ptr.from_mut(allocation)))
        failing.reserve(1usize)
        retained = failing.capacity()
        var index = 0usize
        while index < retained {
            let _ = failing.insert(index as i32, DropValue(core.ptr.from_mut(dropped)))
            index += 1usize
        }
        allocation.fail_grow = true
        match take capture failing.try_insert(-1, DropValue(core.ptr.from_mut(dropped))) {
            success(_) => { return 11 },
            failure(_) => {}
        }
        if failing.len() != retained || dropped != 1usize { return 12 }
    }
    if dropped != retained + 1usize { return 13 }
    0
}
