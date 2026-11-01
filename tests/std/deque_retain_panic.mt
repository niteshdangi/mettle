// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.vec_deque
import std.panic.CatchResult

type Item {
    id: i32
    drops: Arc<core.sync.atomic.AtomicUsize>
    panic_on_drop: bool
    drop {
        let _old = self.drops.get().fetch_add(
            1usize,
            core.sync.atomic.Ordering.SeqCst
        )
        if self.panic_on_drop { panic("deque retain drop") }
    }
}

fn main(): i32 {
    let callback_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var callback_deque = vec_deque.new<Item>()
    callback_deque.reserve(4usize)
    callback_deque.push_back(Item(1, callback_drops.retain(), false))
    callback_deque.push_back(Item(2, callback_drops.retain(), false))
    callback_deque.push_back(Item(3, callback_drops.retain(), false))
    callback_deque.push_back(Item(4, callback_drops.retain(), false))
    {
        let removed = callback_deque.pop_front().unwrap()
    }
    callback_deque.push_back(Item(5, callback_drops.retain(), false))
    let callback = std.panic.catch_panic(fn(): i32 {
        callback_deque.retain(fn(value: read Item): bool {
            if value.id == 3 { panic("deque retain predicate") }
            value.id != 2
        })
        0
    })
    match take callback {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if callback_deque.len() != 3usize ||
        callback_deque[0usize].id != 3 ||
        callback_deque[1usize].id != 4 ||
        callback_deque[2usize].id != 5 { return 2 }
    if callback_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
        return 3
    }
    callback_deque.clear()
    if callback_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize {
        return 4
    }

    let destructor_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var destructor_deque = vec_deque.new<Item>()
    destructor_deque.reserve(4usize)
    destructor_deque.push_back(Item(5, destructor_drops.retain(), false))
    destructor_deque.push_back(Item(6, destructor_drops.retain(), true))
    destructor_deque.push_back(Item(7, destructor_drops.retain(), false))
    destructor_deque.push_back(Item(8, destructor_drops.retain(), false))
    {
        let removed = destructor_deque.pop_front().unwrap()
    }
    destructor_deque.push_back(Item(9, destructor_drops.retain(), false))
    let destructor = std.panic.catch_panic(fn(): i32 {
        destructor_deque.retain(fn(value: read Item): bool {
            value.id != 6
        })
        0
    })
    match take destructor {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 5 }
    }
    if destructor_deque.len() != 3usize ||
        destructor_deque[0usize].id != 7 ||
        destructor_deque[1usize].id != 8 ||
        destructor_deque[2usize].id != 9 { return 6 }
    if destructor_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
        return 7
    }
    destructor_deque.clear()
    if destructor_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize {
        return 8
    }
    0
}
