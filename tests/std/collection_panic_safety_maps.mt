// expect-exit: 0
import alloc.arc
import alloc.arc.Shared
import alloc.btree
import alloc.hash_map
import alloc.alloc.{Allocator, Global, Layout, AllocError}
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
import core.hash.{Hash, Hasher}
import std.panic.CatchResult

type Key {
    value: i32
    panic_hash: Shared<core.sync.atomic.AtomicUsize>
    panic_eq: Shared<core.sync.atomic.AtomicUsize>
    panic_cmp: Shared<core.sync.atomic.AtomicUsize>
}

extend Key implements PartialEq {
    fn eq(read other: Key): bool {
        if self.panic_eq.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("key equality")
        }
        self.value == other.value
    }
}
extend Key implements Eq {}
extend Key implements PartialOrd {
    fn partial_cmp(read other: Key): Ordering? { present(self.cmp(other)) }
}
extend Key implements Ord {
    fn cmp(read other: Key): Ordering {
        let remaining = self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst)
        if remaining == 1usize {
            panic("key comparison")
        }
        if remaining > 1usize {
            let _ = self.panic_cmp.get().fetch_sub(1usize, core.sync.atomic.Ordering.SeqCst)
        }
        self.value.cmp(other.value)
    }
}
extend Key implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        if self.panic_hash.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("key hash")
        }
        state.write_u32(self.value as u32)
    }
}

fn make_key(value: i32, take panic_hash: Shared<core.sync.atomic.AtomicUsize>,
            take panic_eq: Shared<core.sync.atomic.AtomicUsize>,
            take panic_cmp: Shared<core.sync.atomic.AtomicUsize>): Key {
    Key(value, panic_hash, panic_eq, panic_cmp)
}

type DropBomb {
    drops: Shared<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        if self.panic_on_drop { panic("tree value drop") }
    }
}

copy type SplitAllocator {
    calls: ptr<mut i32>
    fail_at: ptr<mut i32>
    live: ptr<mut i32>
    free_fail_at: ptr<mut i32>
}
extend SplitAllocator implements core.clone.Clone {
    fn clone(): SplitAllocator { SplitAllocator(self.calls, self.fail_at, self.live, self.free_fail_at) }
}
unsafe extend SplitAllocator implements Allocator {
    fn is_compatible(read other: SplitAllocator): bool { self.live == other.live }
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            *self.calls += 1
            if *self.calls == *self.fail_at { panic("split allocation") }
        }
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe { *self.live += 1 }
        pointer
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe { *self.live -= 1 }
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
        unsafe {
            if self.free_fail_at != core.ptr.null_mut<i32>() && *self.free_fail_at > 0 {
                *self.free_fail_at -= 1
                if *self.free_fail_at == 0 { panic("tree deallocation") }
            }
        }
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
    let panic_hash = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let panic_eq = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let panic_cmp = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var map = hash_map.new<Key, i32>()

    let _set = panic_hash.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let hashed = std.panic.catch_panic(fn(): i32 {
        let _old = map.insert(make_key(1, panic_hash.retain(), panic_eq.retain(),
                                       panic_cmp.retain()), 1)
        0
    })
    match take hashed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if map.len() != 0usize { return 2 }
    let _set = panic_hash.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    let _old = map.insert(make_key(1, panic_hash.retain(), panic_eq.retain(),
                                   panic_cmp.retain()), 1)
    if map.len() != 1usize { return 3 }

    let _set = panic_eq.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let equal = std.panic.catch_panic(fn(): i32 {
        let _old = map.insert(make_key(1, panic_hash.retain(), panic_eq.retain(),
                                       panic_cmp.retain()), 2)
        0
    })
    match take equal {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 4 }
    }
    let _set = panic_eq.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    if map.len() != 1usize { return 5 }

    let modified = std.panic.catch_panic(fn(): i32 {
        let entry = map.entry(make_key(1, panic_hash.retain(), panic_eq.retain(),
                                       panic_cmp.retain()))
        let _updated = entry.and_modify(take fn(mut value: i32): Unit {
            value += 2
            panic("entry callback")
        })
        0
    })
    match take modified {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 6 }
    }
    match map.get(make_key(1, panic_hash.retain(), panic_eq.retain(),
                           panic_cmp.retain())) {
        present(value) => { if *value != 3 { return 7 } },
        none => { return 8 }
    }

    var tree = btree.new<Key, i32>()
    var value = 0
    while value < 11 {
        let stored = value
        let _old = tree.insert(make_key(value, panic_hash.retain(), panic_eq.retain(),
                                        panic_cmp.retain()), stored)
        value += 1
    }
    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let split = std.panic.catch_panic(fn(): i32 {
        let _old = tree.insert(make_key(99, panic_hash.retain(), panic_eq.retain(),
                                        panic_cmp.retain()), 99)
        0
    })
    match take split {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    if tree.len() != 11usize { return 10 }
    value = 0
    while value < 11 {
        if !tree.contains_key(make_key(value, panic_hash.retain(), panic_eq.retain(),
                                       panic_cmp.retain())) { return 11 }
        value += 1
    }
    let _set = panic_cmp.get().store(5usize, core.sync.atomic.Ordering.SeqCst)
    match take std.panic.catch_panic(fn(): Unit {
        let upper = tree.split_off(make_key(6, panic_hash.retain(), panic_eq.retain(),
                                           panic_cmp.retain()))
    }) {
        CatchResult.Panicked(_) => {},
        _ => { return 23 }
    }
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    if tree.len() != 11usize { return 24 }
    value = 0
    while value < 11 {
        if !tree.contains_key(make_key(value, panic_hash.retain(), panic_eq.retain(),
                                       panic_cmp.retain())) { return 25 }
        value += 1
    }
    var allocation_failure = 1
    while allocation_failure <= 8 {
        var calls = 0
        var fail_at = 0
        var live = 0
        {
            var splitting = btree.new_in<i32, i32, SplitAllocator>(
                SplitAllocator(core.ptr.from_mut(calls), core.ptr.from_mut(fail_at), core.ptr.from_mut(live), core.ptr.null_mut<i32>())
            )
            value = 0
            while value < 128 {
                let _ = splitting.insert(value + 0, value + 0)
                value += 1
            }
            let original_live = live
            fail_at = calls + allocation_failure
            match take std.panic.catch_panic(fn(): Unit {
                let upper = splitting.split_off(64)
            }) {
                CatchResult.Panicked(_) => {},
                _ => { return 26 }
            }
            fail_at = 0
            if splitting.len() != 128usize || live != original_live { return 27 }
            value = 0
            while value < 128 {
                if *splitting.get(value).or_panic() != value { return 28 }
                value += 1
            }
        }
        if live != 0 { return 29 }
        allocation_failure += 1
    }
    for comparison_failure in [1usize, 64usize, 127usize] {
        var left = btree.new<Key, i32>()
        var right = btree.new<Key, i32>()
        value = 0
        while value < 64 {
            let _ = left.insert(make_key(value * 2, panic_hash.retain(), panic_eq.retain(),
                                         panic_cmp.retain()), value * 2)
            let _ = right.insert(make_key(value * 2 + 1, panic_hash.retain(), panic_eq.retain(),
                                          panic_cmp.retain()), value * 2 + 1)
            value += 1
        }
        let _ = panic_cmp.get().store(comparison_failure, core.sync.atomic.Ordering.SeqCst)
        match take std.panic.catch_panic(fn(): Unit { left.append(mut right) }) {
            CatchResult.Panicked(_) => {},
            _ => { return 30 }
        }
        let _ = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
        if left.len() != 64usize || right.len() != 64usize { return 31 }
        value = 0
        while value < 64 {
            if *left.get(make_key(value * 2, panic_hash.retain(), panic_eq.retain(),
                                  panic_cmp.retain())).or_panic() != value * 2 ||
                *right.get(make_key(value * 2 + 1, panic_hash.retain(), panic_eq.retain(),
                                   panic_cmp.retain())).or_panic() != value * 2 + 1 { return 32 }
            value += 1
        }
    }
    allocation_failure = 1
    while allocation_failure <= 3 {
        var calls = 0
        var fail_at = 0
        var live = 0
        {
            var left = btree.new_in<i32, i32, SplitAllocator>(
                SplitAllocator(core.ptr.from_mut(calls), core.ptr.from_mut(fail_at), core.ptr.from_mut(live), core.ptr.null_mut<i32>())
            )
            var right = btree.new_in<i32, i32, SplitAllocator>(
                SplitAllocator(core.ptr.from_mut(calls), core.ptr.from_mut(fail_at), core.ptr.from_mut(live), core.ptr.null_mut<i32>())
            )
            value = 0
            while value < 6 {
                let _ = left.insert(value * 2, value * 2)
                let _ = right.insert(value * 2 + 1, value * 2 + 1)
                value += 1
            }
            let original_live = live
            fail_at = calls + allocation_failure
            match take std.panic.catch_panic(fn(): Unit { left.append(mut right) }) {
                CatchResult.Panicked(_) => {},
                _ => { return 33 }
            }
            fail_at = 0
            if left.len() != 6usize || right.len() != 6usize || live != original_live { return 34 }
            value = 0
            while value < 6 {
                if left.pop_first() != present((value * 2, value * 2)) ||
                    right.pop_first() != present((value * 2 + 1, value * 2 + 1)) { return 35 }
                value += 1
            }
        }
        if live != 0 { return 36 }
        allocation_failure += 1
    }
    for deallocation_failure in [1, 3, 7, 31] {
        var calls = 0
        var fail_at = 0
        var live = 0
        var free_fail_at = 0
        {
            var left = btree.new_in<i32, i32, SplitAllocator>(
                SplitAllocator(core.ptr.from_mut(calls), core.ptr.from_mut(fail_at), core.ptr.from_mut(live), core.ptr.from_mut(free_fail_at))
            )
            var right = btree.new_in<i32, i32, SplitAllocator>(
                SplitAllocator(core.ptr.from_mut(calls), core.ptr.from_mut(fail_at), core.ptr.from_mut(live), core.ptr.from_mut(free_fail_at))
            )
            value = 0
            while value < 64 {
                let _ = left.insert(value + 0, value + 0)
                let _ = right.insert(value + 0, -value - 1)
                value += 1
            }
            free_fail_at = deallocation_failure
            match take std.panic.catch_panic(fn(): Unit { left.append(mut right) }) {
                CatchResult.Panicked(_) => {},
                _ => { return 41 }
            }
            if left.len() != 64usize || !right.is_empty() || free_fail_at != 0 { return 42 }
            value = 0
            while value < 64 {
                if *left.get(value).or_panic() != -value - 1 { return 43 }
                value += 1
            }
            left.clear()
        }
        if live != 0 { return 44 }
    }
    let append_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    {
        var left = btree.new<i32, DropBomb>()
        var right = btree.new<i32, DropBomb>()
        let _ = left.insert(1, DropBomb(append_drops.retain(), true))
        let _ = left.insert(2, DropBomb(append_drops.retain(), false))
        let _ = left.insert(3, DropBomb(append_drops.retain(), false))
        let _ = right.insert(1, DropBomb(append_drops.retain(), false))
        let _ = right.insert(2, DropBomb(append_drops.retain(), false))
        let _ = right.insert(4, DropBomb(append_drops.retain(), false))
        match take std.panic.catch_panic(fn(): Unit { left.append(mut right) }) {
            CatchResult.Panicked(_) => {},
            _ => { return 37 }
        }
        if left.len() != 4usize || !right.is_empty() ||
            append_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize ||
            left.get(1).or_panic().panic_on_drop { return 38 }
        value = 1
        while value <= 4 {
            if !left.contains_key(value) { return 39 }
            value += 1
        }
    }
    if append_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 6usize { return 40 }

    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var dropping = btree.new<i32, DropBomb>()
    let _old = dropping.insert(1, DropBomb(drops.retain(), true))
    let _old = dropping.insert(2, DropBomb(drops.retain(), false))
    let cleared = std.panic.catch_panic(fn(): i32 {
        dropping.clear()
        0
    })
    match take cleared {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 12 }
    }
    if dropping.len() != 0usize { return 13 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
        return 14
    }
    let _old = dropping.insert(3, DropBomb(drops.retain(), false))
    dropping.clear()
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize {
        return 15
    }

    let retain_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var retaining = hash_map.new<i32, DropBomb>()
    let _old = retaining.insert(1, DropBomb(retain_drops.retain(), false))
    let _old = retaining.insert(2, DropBomb(retain_drops.retain(), false))
    let _old = retaining.insert(3, DropBomb(retain_drops.retain(), false))
    var retain_calls = 0
    let retain_panic = std.panic.catch_panic(fn(): i32 {
        retaining.retain(fn(read key: i32, mut value: DropBomb): bool {
            retain_calls += 1
            if retain_calls == 1 { false } else { panic("retain callback") }
        })
        0
    })
    match take retain_panic {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 16 }
    }
    if retain_calls != 2 || retaining.len() != 2usize ||
        retain_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize {
        return 17
    }
    var remaining = 0
    var key = 1
    while key <= 3 {
        if retaining.contains_key(key) { remaining += 1 }
        key += 1
    }
    if remaining != 2 { return 18 }
    retaining.clear()
    if retain_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize {
        return 19
    }

    let tree_retain_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var retaining_tree = btree.new<i32, DropBomb>()
    let _old = retaining_tree.insert(1, DropBomb(tree_retain_drops.retain(), false))
    let _old = retaining_tree.insert(2, DropBomb(tree_retain_drops.retain(), false))
    let _old = retaining_tree.insert(3, DropBomb(tree_retain_drops.retain(), false))
    retain_calls = 0
    let tree_retain_panic = std.panic.catch_panic(fn(): i32 {
        retaining_tree.retain(fn(read key: i32, mut value: DropBomb): bool {
            retain_calls += 1
            if retain_calls == 1 { false } else { panic("retain callback") }
        })
        0
    })
    match take tree_retain_panic {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 20 }
    }
    if retain_calls != 2 || retaining_tree.len() != 2usize ||
        tree_retain_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize ||
        retaining_tree.contains_key(1) ||
        !retaining_tree.contains_key(2) || !retaining_tree.contains_key(3) {
        return 21
    }
    retaining_tree.clear()
    if tree_retain_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize {
        return 22
    }
    0
}
