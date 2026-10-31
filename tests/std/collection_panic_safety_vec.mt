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

fn main(): i32 {
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
        numbers.retain(fn(value: read i32): bool {
            if value == 2 { panic("retain callback") }
            true
        })
        0
    })
    match take retained {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if numbers.len() != 0usize { return 6 }
    numbers.push(4)
    match numbers.pop() {
        present(value) => { if value != 4 { return 7 } },
        none => { return 8 }
    }

    var stable = vec.new<i32>()
    stable.push(3)
    stable.push(1)
    stable.push(2)
    let sorted = std.panic.catch_panic(fn(): i32 {
        stable.sort_by(fn(a: read i32, b: read i32): Ordering {
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
        slice.sort_unstable_by(fn(a: read i32, b: read i32): Ordering {
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
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize {
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
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
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
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize {
        return 22
    }
    {
        let value = match take deque.pop_front() {
            present(item) => item,
            none => { return 23 }
        }
        if value.panic_on_drop { return 24 }
    }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 4usize {
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
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize {
        return 28
    }
    {
        let value = match take linked.pop_front() {
            present(item) => item,
            none => { return 29 }
        }
        if value.panic_on_drop { return 30 }
    }
    if drop_count.get().load(core.sync.atomic.Ordering.SeqCst) != 6usize {
        return 31
    }
    0
}
