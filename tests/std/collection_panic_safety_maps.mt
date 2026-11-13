// expect-exit: 0
import alloc.arc
import alloc.arc.Shared
import alloc.btree
import alloc.hash_map
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
        if self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("key comparison")
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
