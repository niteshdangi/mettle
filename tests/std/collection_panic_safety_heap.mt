// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.binary_heap
import core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }
import std.panic.CatchResult

type Item {
    value: i32
    panic_cmp: Arc<core.sync.atomic.AtomicUsize>
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

extend Item implements PartialEq {
    fn eq(other: read Item): bool { self.value == other.value }
}
extend Item implements Eq {}
extend Item implements PartialOrd {
    fn partial_cmp(other: read Item): Ordering? { present(self.cmp(other)) }
}
extend Item implements Ord {
    fn cmp(other: read Item): Ordering {
        if self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("heap comparison")
        }
        self.value.cmp(other.value)
    }
}

fn new_item(value: i32, panic_cmp: take Arc<core.sync.atomic.AtomicUsize>,
    drops: take Arc<core.sync.atomic.AtomicUsize>): Item {
    Item(value, panic_cmp, drops)
}

fn main(): i32 {
    let panic_cmp = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var queue = binary_heap.new<Item>()
    queue.push(new_item(10, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(5, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(1, panic_cmp.retain(), drops.retain()))

    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let pushed = std.panic.catch_panic(fn(): i32 {
        queue.push(new_item(99, panic_cmp.retain(), drops.retain()))
        0
    })
    match take pushed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if queue.len() != 3usize { return 2 }

    let popped = std.panic.catch_panic(fn(): i32 {
        let _item = queue.pop()
        0
    })
    match take popped {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    if queue.len() != 3usize { return 4 }
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)

    let expected = [10, 5, 1]
    var index = 0usize
    while index < 3usize {
        let item = match take queue.pop() {
            present(value) => value,
            none => { return 5 }
        }
        if item.value != expected[index] { return 6 }
        index += 1usize
    }
    if !queue.is_empty() { return 7 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 4usize {
        return 8
    }

    var retained = binary_heap.new<Item>()
    retained.push(new_item(10, panic_cmp.retain(), drops.retain()))
    retained.push(new_item(5, panic_cmp.retain(), drops.retain()))
    retained.push(new_item(1, panic_cmp.retain(), drops.retain()))
    let predicate_panic = std.panic.catch_panic(fn(): Unit {
        retained.retain(fn(value: read Item): bool {
            if value.value == 5 { panic("heap retain predicate") }
            false
        })
    })
    match take predicate_panic {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    if retained.len() != 3usize { return 10 }
    let retained_expected = [10, 5, 1]
    var retained_index = 0usize
    while retained_index < 3usize {
        let item = match take retained.pop() {
            present(value) => value,
            none => { return 11 }
        }
        if item.value != retained_expected[retained_index] { return 12 }
        retained_index += 1usize
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 7usize {
        return 13
    }

    var comparison_retained = binary_heap.new<Item>()
    comparison_retained.push(new_item(20, panic_cmp.retain(), drops.retain()))
    comparison_retained.push(new_item(10, panic_cmp.retain(), drops.retain()))
    comparison_retained.push(new_item(5, panic_cmp.retain(), drops.retain()))
    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let comparison_panic = std.panic.catch_panic(fn(): Unit {
        comparison_retained.retain(fn(value: read Item): bool {
            value.value != 5
        })
    })
    match take comparison_panic {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 14 }
    }
    if comparison_retained.len() != 3usize { return 15 }
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    let comparison_expected = [20, 10, 5]
    var comparison_index = 0usize
    while comparison_index < 3usize {
        let item = match take comparison_retained.pop() {
            present(value) => value,
            none => { return 16 }
        }
        if item.value != comparison_expected[comparison_index] { return 17 }
        comparison_index += 1usize
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 10usize {
        return 18
    }
    0
}
