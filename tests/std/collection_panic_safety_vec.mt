// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.linked_list
import alloc.vec
import alloc.vec_deque
import core.clone.Clone
import core.cmp.Ordering
import std.panic.CatchResult

type CloneBomb {
    id: i32
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

extend CloneBomb implements Clone {
    fn clone(): CloneBomb {
        if self.id == 1 { panic("clone callback") }
        CloneBomb(self.id, self.drops.retain())
    }
}

type DropBomb {
    drops: Arc<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        if self.panic_on_drop { panic("drop callback") }
    }
}

type RetainBomb {
    id: i32
    drops: Arc<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        if self.panic_on_drop { panic("retain drop callback") }
    }
}

type DedupBomb {
    id: i32
    drops: Arc<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        if self.panic_on_drop { panic("dedup drop callback") }
    }
}

fn dedup_unwind(callback_panic: bool): Unit {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var values = vec.new<DedupBomb>()
    if callback_panic {
        values.push(DedupBomb(1, drops.retain(), false))
        values.push(DedupBomb(1, drops.retain(), false))
        values.push(DedupBomb(2, drops.retain(), false))
        values.push(DedupBomb(3, drops.retain(), false))
        values.push(DedupBomb(4, drops.retain(), false))
    } else {
        values.push(DedupBomb(1, drops.retain(), false))
        values.push(DedupBomb(1, drops.retain(), true))
        values.push(DedupBomb(2, drops.retain(), false))
        values.push(DedupBomb(2, drops.retain(), false))
        values.push(DedupBomb(3, drops.retain(), false))
    }
    let pointer = values.as_ptr()
    let capacity = values.capacity()
    var visits = 0usize
    let result = std.panic.catch_panic(fn(): Unit {
        if callback_panic {
            values.dedup_by(fn(mut current: DedupBomb, mut previous: DedupBomb): bool {
                visits += 1usize
                if current.id == 3 { panic("dedup predicate") }
                current.id == previous.id
            })
        } else {
            values.dedup_by(fn(mut current: DedupBomb, mut previous: DedupBomb): bool {
                visits += 1usize
                current.id == previous.id
            })
        }
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { panic("dedup must propagate the panic") }
    }
    assert(values.as_ptr() == pointer && values.capacity() == capacity,
        "dedup unwind preserves allocation")
    if callback_panic {
        assert(visits == 3usize && values.len() == 4usize,
            "dedup callback panic restores kept and unvisited items")
        assert(values[0usize].id == 1 && values[1usize].id == 2 &&
            values[2usize].id == 3 && values[3usize].id == 4,
            "dedup callback panic compacts initialized values")
    } else {
        assert(visits == 1usize && values.len() == 4usize,
            "dedup destructor panic restores the unvisited suffix")
        assert(values[0usize].id == 1 && values[1usize].id == 2 &&
            values[2usize].id == 2 && values[3usize].id == 3,
            "dedup destructor panic preserves every live value")
    }
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 1usize,
        "dedup panic drops the removed duplicate once")
    values.clear()
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 5usize,
        "dedup panic recovery drops all remaining values")
    values.push(DedupBomb(9, drops.retain(), false))
    values.clear()
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 6usize,
        "dedup panic recovery leaves vector reusable")
}

fn retain_unwind(mutable_predicate: bool, panic_on_drop: bool): Unit {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var values = vec.new<RetainBomb>()
    var id = 0
    while id < 7 {
        values.push(RetainBomb(id + 0, drops.retain(), panic_on_drop && id == 3))
        id += 1
    }
    let pointer = values.as_ptr()
    let capacity = values.capacity()
    var visits = 0
    let result = std.panic.catch_panic(fn(): Unit {
        if mutable_predicate {
            values.retain_mut(fn(mut value: RetainBomb): bool {
                visits += 1
                value.id += 10
                if value.id == 15 { panic("retain_mut callback") }
                value.id % 2 == 0
            })
        } else {
            values.retain(fn(read value: RetainBomb): bool {
                visits += 1
                if value.id == 5 { panic("retain callback after removal") }
                value.id % 2 == 0
            })
        }
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { panic("retain must propagate the panic") }
    }
    assert(visits == if panic_on_drop { 4 } else { 6 }, "retain stops at panic")
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 2usize,
        "removed values dropped once")
    assert(values.len() == 5usize, "retain preserves kept and unvisited elements")
    assert(values.as_ptr() == pointer && values.capacity() == capacity,
        "retain recovery keeps allocation")
    assert(values[0usize].id == if mutable_predicate { 10 } else { 0 }, "retained prefix")
    assert(values[1usize].id == if mutable_predicate { 12 } else { 2 }, "compacted prefix")
    assert(values[2usize].id == if mutable_predicate && !panic_on_drop { 14 } else { 4 },
        "compacted tail")
    assert(values[3usize].id == if mutable_predicate && !panic_on_drop { 15 } else { 5 },
        "panicking element")
    assert(values[4usize].id == 6, "unvisited tail")
    values.clear()
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 7usize,
        "no leaked or double-dropped elements")
    values.push(RetainBomb(7, drops.retain(), false))
    values.clear()
    assert(drops.get().load(core.sync.atomic.Ordering.SeqCst) == 8usize, "list remains reusable")
}

fn main(): i32 {
    dedup_unwind(true)
    dedup_unwind(false)
    retain_unwind(false, false)
    retain_unwind(true, false)
    retain_unwind(false, true)
    retain_unwind(true, true)
    let clone_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var originals = vec.new<CloneBomb>()
    originals.push(CloneBomb(0, clone_drops.retain()))
    originals.push(CloneBomb(1, clone_drops.retain()))
    originals.push(CloneBomb(2, clone_drops.retain()))
    let cloned = std.panic.catch_panic(fn(): i32 {
        let _copy = originals.clone()
        0
    })
    match take cloned {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if originals.len() != 3usize { return 2 }
    if clone_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize {
        return 3
    }
    originals.clear()
    if clone_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 4usize {
        return 4
    }

    var numbers = vec.new<i32>()
    numbers.push(1)
    numbers.push(2)
    numbers.push(3)
    let retained = std.panic.catch_panic(fn(): i32 {
        numbers.retain(fn(read value: i32): bool {
            if value == 2 { panic("retain callback") }
            true
        })
        0
    })
    match take retained {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if numbers.len() != 3usize || numbers[0usize] != 1 ||
        numbers[1usize] != 2 || numbers[2usize] != 3 { return 6 }
    numbers.push(4)
    match numbers.pop() {
        present(value) => { if value != 4 { return 7 } },
        none => { return 8 }
    }
    let first = std.panic.catch_panic(fn(): Unit {
        numbers.retain_mut(fn(mut value: i32): bool {
            value += 10
            panic("retain_mut first callback")
            true
        })
    })
    match take first {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 32 }
    }
    if numbers.len() != 3usize || numbers[0usize] != 11 ||
        numbers[1usize] != 2 || numbers[2usize] != 3 { return 33 }

    var stable = vec.new<i32>()
    stable.push(3)
    stable.push(1)
    stable.push(2)
    let sorted = std.panic.catch_panic(fn(): i32 {
        stable.sort_by(fn(read a: i32, read b: i32): Ordering {
            panic("stable comparison")
            Ordering.Equal
        })
        0
    })
    match take sorted {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    if stable[0usize] != 3 || stable[1usize] != 1 || stable[2usize] != 2 {
        return 10
    }
    stable.sort()
    if stable[0usize] != 1 || stable[1usize] != 2 || stable[2usize] != 3 {
        return 11
    }

    var raw = [3, 1, 2]
    let unstable = std.panic.catch_panic(fn(): i32 {
        let slice = mut raw[0usize..3usize]
        slice.sort_unstable_by(fn(read a: i32, read b: i32): Ordering {
            panic("unstable comparison")
            Ordering.Equal
        })
        0
    })
    match take unstable {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 12 }
    }
    let slice = mut raw[0usize..3usize]
    slice.sort_unstable()
    if raw[0usize] != 1 || raw[1usize] != 2 || raw[2usize] != 3 {
        return 13
    }

    let drop_count = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var values = vec.new<DropBomb>()
    values.push(DropBomb(drop_count.retain(), true))
    values.push(DropBomb(drop_count.retain(), false))
    let cleared = std.panic.catch_panic(fn(): i32 {
        values.clear()
        0
    })
    match take cleared {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 14 }
    }
    if values.len() != 0usize { return 15 }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
        return 16
    }
    values.push(DropBomb(drop_count.retain(), false))
    {
        let value = match take values.pop() {
            present(item) => item,
            none => { return 17 }
        }
        if value.panic_on_drop { return 18 }
    }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize {
        return 19
    }

    var deque = vec_deque.new<DropBomb>()
    deque.push_back(DropBomb(drop_count.retain(), true))
    deque.push_back(DropBomb(drop_count.retain(), false))
    let deque_cleared = std.panic.catch_panic(fn(): i32 {
        deque.clear()
        0
    })
    match take deque_cleared {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 20 }
    }
    if deque.len() != 1usize { return 21 }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 4usize {
        return 22
    }
    {
        let value = match take deque.pop_front() {
            present(item) => item,
            none => { return 23 }
        }
        if value.panic_on_drop { return 24 }
    }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize {
        return 25
    }

    var linked = linked_list.new<DropBomb>()
    linked.push_back(DropBomb(drop_count.retain(), true))
    linked.push_back(DropBomb(drop_count.retain(), false))
    let linked_cleared = std.panic.catch_panic(fn(): i32 {
        linked.clear()
        0
    })
    match take linked_cleared {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 26 }
    }
    if linked.len() != 1usize { return 27 }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 6usize {
        return 28
    }
    {
        let value = match take linked.pop_front() {
            present(item) => item,
            none => { return 29 }
        }
        if value.panic_on_drop { return 30 }
    }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 7usize {
        return 31
    }
    0
}
