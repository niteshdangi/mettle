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
        let _old = self.drops.get().fetch_add(
            1usize,
            core.sync.atomic.Ordering.SeqCst
        )
    }
}

extend Item implements PartialEq {
    fn eq(other: read Item): bool { self.value == other.value }
}
extend Item implements Eq {}
extend Item implements PartialOrd {
    fn partial_cmp(other: read Item): Ordering? {
        present(self.cmp(other))
    }
}
extend Item implements Ord {
    fn cmp(other: read Item): Ordering {
        if self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("heap append comparison")
        }
        self.value.cmp(other.value)
    }
}

fn new_item(
    value: i32,
    panic_cmp: take Arc<core.sync.atomic.AtomicUsize>,
    drops: take Arc<core.sync.atomic.AtomicUsize>
): Item {
    Item(value, panic_cmp, drops)
}

fn main(): i32 {
    let panic_cmp = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var left = binary_heap.new<Item>()
    var right = binary_heap.new<Item>()
    left.push(new_item(10, panic_cmp.retain(), drops.retain()))
    left.push(new_item(5, panic_cmp.retain(), drops.retain()))
    left.push(new_item(1, panic_cmp.retain(), drops.retain()))
    right.push(new_item(9, panic_cmp.retain(), drops.retain()))
    right.push(new_item(6, panic_cmp.retain(), drops.retain()))
    right.push(new_item(2, panic_cmp.retain(), drops.retain()))

    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let result = std.panic.catch_panic(fn(): Unit {
        left.append(right)
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    if left.len() != 3usize || right.len() != 3usize { return 2 }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
        return 3
    }

    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    left.append(right)
    if !right.is_empty() || left.len() != 6usize { return 4 }
    let expected_values = [10, 9, 6, 5, 2, 1]
    let expected: read [i32] = read expected_values
    var index = 0usize
    while index < expected.len() {
        let item = match take left.pop() {
            present(value) => value,
            none => { return 5 }
        }
        if item.value != expected[index] { return 6 }
        index += 1usize
    }
    if !left.is_empty() ||
        drops.get().load(core.sync.atomic.Ordering.SeqCst) != 6usize {
        return 7
    }
    0
}
