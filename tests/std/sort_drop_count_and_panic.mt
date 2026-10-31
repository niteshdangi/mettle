// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.vec
import core.cmp.Ordering
import std.panic.CatchResult

// Counts every drop so a sort that duplicates, leaks or double-drops an
// element is visible.
type Tracked {
    key: i32
    tag: i32
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

fn fill(items: mut vec.List<Tracked>, drops: read Arc<core.sync.atomic.AtomicUsize>): Unit {
    items.push(Tracked(2, 0, drops.retain()))
    items.push(Tracked(1, 1, drops.retain()))
    items.push(Tracked(2, 2, drops.retain()))
    items.push(Tracked(1, 3, drops.retain()))
    items.push(Tracked(0, 4, drops.retain()))
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var items = vec.new<Tracked>()
    fill(mut items, read drops)

    // A successful stable sort moves elements without dropping any and keeps
    // equal keys in their original order: tags 4, 1, 3, 0, 2.
    items.sort_by_key(fn(item: read Tracked): i32 { item.key })
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 1 }
    if items.len() != 5usize { return 2 }
    if items[0usize].tag != 4 || items[1usize].tag != 1 || items[2usize].tag != 3 { return 3 }
    if items[3usize].tag != 0 || items[4usize].tag != 2 { return 4 }

    // Sorting by a cached key also drops nothing and is stable.
    items.sort_by_cached_key(fn(item: read Tracked): i32 { 0 - item.tag })
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 5 }
    if items[0usize].tag != 4 || items[4usize].tag != 0 { return 6 }

    // A comparison that panics leaves every element in place and alive.
    let panicked = std.panic.catch_panic(fn(): i32 {
        items.sort_by(fn(a: read Tracked, b: read Tracked): Ordering {
            panic("sort comparison")
            Ordering.Equal
        })
        0
    })
    match take panicked {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    if items.len() != 5usize { return 8 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 9 }
    if items[0usize].tag != 4 || items[4usize].tag != 0 { return 10 }

    // A panicking key function must not drop or duplicate elements either.
    let key_panicked = std.panic.catch_panic(fn(): i32 {
        items.sort_by_key(fn(item: read Tracked): i32 {
            panic("sort key")
            item.key
        })
        0
    })
    match take key_panicked {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 11 }
    }
    if items.len() != 5usize { return 12 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 13 }

    // Every element is destroyed exactly once, when the list is cleared.
    items.clear()
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize { return 14 }

    // A sorted list that goes out of scope drops each element once.
    let scoped_drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    {
        var scoped = vec.new<Tracked>()
        fill(mut scoped, read scoped_drops)
        scoped.sort_by_key(fn(item: read Tracked): i32 { item.key })
        if scoped_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 15 }
    }
    if scoped_drops.get().load(core.sync.atomic.Ordering.SeqCst) != 5usize { return 16 }
    0
}
