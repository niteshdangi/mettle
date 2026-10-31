// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.binary_heap
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}
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
    var heap = binary_heap.new<Item>()
    heap.push(new_item(10, panic_cmp.retain(), drops.retain()))
    heap.push(new_item(5, panic_cmp.retain(), drops.retain()))
    heap.push(new_item(1, panic_cmp.retain(), drops.retain()))

    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let pushed = std.panic.catch_panic(fn(): i32 {
        heap.push(new_item(99, panic_cmp.retain(), drops.retain()))
        0
    })
    match take pushed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if heap.len() != 3usize { return 2 }

    let popped = std.panic.catch_panic(fn(): i32 {
        let _item = heap.pop()
        0
    })
    match take popped {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    if heap.len() != 3usize { return 4 }
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)

    let expected = [10, 5, 1]
    var index = 0usize
    while index < expected.len() {
        let item = match heap.pop() {
            present(value) => value,
            none => { return 5 }
        }
        if item.value != expected[index] { return 6 }
        index += 1usize
    }
    if !heap.is_empty() { return 7 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 4usize {
        return 8
    }
    0
}
