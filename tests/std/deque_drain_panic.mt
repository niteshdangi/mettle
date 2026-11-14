// expect-exit: 0
import alloc.arc
import alloc.arc.Shared
import alloc.vec_deque
import core.iter.Bound
import std.panic.CatchResult

type Item {
    id: i32
    drops: Shared<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(
            1usize,
            core.sync.atomic.Ordering.SeqCst
        )
        if self.panic_on_drop { panic("deque drain drop") }
    }
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var deque = vec_deque.new<Item>()
    deque.reserve(5usize)
    deque.push_back(Item(1, drops.retain(), false))
    deque.push_back(Item(2, drops.retain(), false))
    deque.push_back(Item(3, drops.retain(), false))
    deque.push_back(Item(4, drops.retain(), true))
    deque.push_back(Item(5, drops.retain(), false))

    let result = std.panic.catch_panic(fn(): i32 {
        var drain = deque.drain(2usize..4usize)
        match take drain.next() {
            present(item) => { if item.id != 3 { return 1 } },
            none => { return 2 }
        }
        0
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    if deque.len() != 3usize || deque[0usize].id != 1 ||
        deque[1usize].id != 2 || deque[2usize].id != 5 {
        return 4
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
        return 5
    }
    deque.clear()
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize {
        return 6
    }

    var unchanged = vec_deque.new<i32>()
    unchanged.push_back(1)
    unchanged.push_back(2)
    let reversed = std.panic.catch_panic(fn(): i32 {
        let _drain = unchanged.drain(2usize..1usize)
        0
    })
    match take reversed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if unchanged.len() != 2usize || unchanged[0usize] != 1 ||
        unchanged[1usize] != 2 {
        return 8
    }
    let overflow = std.panic.catch_panic(fn(): i32 {
        let bounds: (Bound<usize>, Bound<usize>) = (
            Bound.Excluded(0xffffffffffffffffusize),
            Bound.Unbounded
        )
        let _drain = unchanged.drain(bounds)
        0
    })
    match take overflow {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    if unchanged.len() != 2usize || unchanged[0usize] != 1 ||
        unchanged[1usize] != 2 {
        return 10
    }
    let end_overflow = std.panic.catch_panic(fn(): i32 {
        let _drain = unchanged.drain(core.iter.range_to_inclusive(0xffffffffffffffffusize))
        0
    })
    match take end_overflow {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 11 }
    }
    if unchanged.len() != 2usize || unchanged[0usize] != 1 ||
        unchanged[1usize] != 2 {
        return 12
    }
    0
}
