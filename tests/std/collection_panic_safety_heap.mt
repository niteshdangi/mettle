// expect-exit: 0
import alloc.arc
import alloc.arc.Arc
import alloc.binary_heap
import core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }
import std.panic.CatchResult

type Item {
    value: i32
    drop_bit: usize
    panic_cmp: Arc<core.sync.atomic.AtomicUsize>
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop {
        // Bit 7 records repeated destruction; lower bits identify individual items.
        let old = self.drops.get().load(core.sync.atomic.Ordering.SeqCst)
        self.drops.get().store(
            if (old & self.drop_bit) != 0usize { 128usize } else { old | self.drop_bit },
            core.sync.atomic.Ordering.SeqCst
        )
    }
}

extend Item implements PartialEq {
    fn eq(read other: Item): bool { self.value == other.value }
}
extend Item implements Eq {}
extend Item implements PartialOrd {
    fn partial_cmp(read other: Item): Ordering? { present(self.cmp(other)) }
}
extend Item implements Ord {
    fn cmp(read other: Item): Ordering {
        if self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("heap comparison")
        }
        self.value.cmp(other.value)
    }
}

fn new_item(value: i32, drop_bit: usize, take panic_cmp: Arc<core.sync.atomic.AtomicUsize>,
    take drops: Arc<core.sync.atomic.AtomicUsize>): Item {
    Item(value, drop_bit, panic_cmp, drops)
}

fn accounted(read items: [Item], read expected: [i32], dropped: usize): bool {
    var live = 0usize
    var index = 0usize
    while index < items.len() {
        var found = false
        var identity = 0usize
        while identity < expected.len() {
            let bit = 1usize << identity
            if items[index].drop_bit == bit && items[index].value == expected[identity] {
                if (live & bit) != 0usize { return false }
                live |= bit
                found = true
                break
            }
            identity += 1usize
        }
        if !found { return false }
        index += 1usize
    }
    (live & dropped) == 0usize && (live | dropped) == (1usize << expected.len()) - 1usize
}

fn main(): i32 {
    let panic_cmp = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    var queue = binary_heap.new<Item>()
    queue.push(new_item(10, 1usize, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(5, 2usize, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(1, 4usize, panic_cmp.retain(), drops.retain()))

    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let pushed = std.panic.catch_panic(fn(): i32 {
        queue.push(new_item(99, 8usize, panic_cmp.retain(), drops.retain()))
        0
    })
    match take pushed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    let pushed_items = queue.into_vec()
    let push_expected = [10, 5, 1, 99]
    if !accounted(pushed_items.as_slice(), read push_expected,
        drops.get().load(core.sync.atomic.Ordering.SeqCst)) { return 2 }
    core.mem.drop(pushed_items)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 15usize { return 8 }

    drops.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    var queue = binary_heap.new<Item>()
    queue.push(new_item(10, 1usize, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(5, 2usize, panic_cmp.retain(), drops.retain()))
    queue.push(new_item(1, 4usize, panic_cmp.retain(), drops.retain()))
    panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let popped = std.panic.catch_panic(fn(): i32 {
        let _item = queue.pop()
        0
    })
    match take popped {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 3 }
    }
    let expected = [10, 5, 1]
    let popped_items = queue.into_vec()
    if !accounted(popped_items.as_slice(), read expected,
        drops.get().load(core.sync.atomic.Ordering.SeqCst)) { return 4 }
    core.mem.drop(popped_items)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 7usize { return 8 }

    drops.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    var retained = binary_heap.new<Item>()
    retained.push(new_item(10, 1usize, panic_cmp.retain(), drops.retain()))
    retained.push(new_item(5, 2usize, panic_cmp.retain(), drops.retain()))
    retained.push(new_item(1, 4usize, panic_cmp.retain(), drops.retain()))
    let predicate_panic = std.panic.catch_panic(fn(): Unit {
        retained.retain(fn(read value: Item): bool {
            if value.value == 5 { panic("heap retain predicate") }
            false
        })
    })
    match take predicate_panic {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 9 }
    }
    let retained_items = retained.into_vec()
    if !accounted(retained_items.as_slice(), read expected,
        drops.get().load(core.sync.atomic.Ordering.SeqCst)) { return 10 }
    core.mem.drop(retained_items)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 7usize {
        return 13
    }

    drops.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    var comparison_retained = binary_heap.new<Item>()
    comparison_retained.push(new_item(20, 1usize, panic_cmp.retain(), drops.retain()))
    comparison_retained.push(new_item(10, 2usize, panic_cmp.retain(), drops.retain()))
    comparison_retained.push(new_item(5, 4usize, panic_cmp.retain(), drops.retain()))
    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let comparison_panic = std.panic.catch_panic(fn(): Unit {
        comparison_retained.retain(fn(read value: Item): bool {
            value.value != 5
        })
    })
    let comparison_panicked = match take comparison_panic {
        CatchResult.Panicked(_) => true,
        CatchResult.Returned(_) => false
    }
    if !comparison_panicked {
        match comparison_retained.peek() {
            present(item) => { if item.value != 20 { return 14 } },
            none => { return 14 }
        }
    }
    let comparison_items = comparison_retained.into_vec()
    let comparison_expected = [20, 10, 5]
    let comparison_drops = drops.get().load(core.sync.atomic.Ordering.SeqCst)
    if !accounted(comparison_items.as_slice(), read comparison_expected,
        comparison_drops) { return 15 }
    if !comparison_panicked && (comparison_items.len() != 2usize || comparison_drops != 4usize) {
        return 14
    }
    core.mem.drop(comparison_items)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 7usize {
        return 18
    }
    0
}
