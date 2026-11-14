// expect-exit: 0
import alloc.arc
import alloc.arc.Shared
import alloc.binary_heap
import core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }
import std.panic.CatchResult

type Item {
    value: i32
    drop_bit: usize
    panic_cmp: Shared<core.sync.atomic.AtomicUsize>
    drops: Shared<core.sync.atomic.AtomicUsize>
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
    fn partial_cmp(read other: Item): Ordering? {
        present(self.cmp(other))
    }
}
extend Item implements Ord {
    fn cmp(read other: Item): Ordering {
        if self.panic_cmp.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
            panic("heap append comparison")
        }
        self.value.cmp(other.value)
    }
}

fn new_item(
    value: i32,
    drop_bit: usize,
    take panic_cmp: Shared<core.sync.atomic.AtomicUsize>,
    take drops: Shared<core.sync.atomic.AtomicUsize>
): Item {
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
    var left = binary_heap.new<Item>()
    var right = binary_heap.new<Item>()
    left.push(new_item(10, 1usize, panic_cmp.retain(), drops.retain()))
    left.push(new_item(5, 2usize, panic_cmp.retain(), drops.retain()))
    left.push(new_item(1, 4usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(9, 8usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(6, 16usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(2, 32usize, panic_cmp.retain(), drops.retain()))

    let _set = panic_cmp.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    let result = std.panic.catch_panic(fn(): Unit {
        left.append(right)
    })
    match take result {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 1 }
    }
    var items = left.into_vec()
    var donor_items = right.into_vec()
    items.append(mut donor_items)
    let identities = [10, 5, 1, 9, 6, 2]
    if !accounted(items.as_slice(), read identities,
        drops.get().load(core.sync.atomic.Ordering.SeqCst)) { return 2 }
    core.mem.drop(items)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 63usize { return 3 }

    drops.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    let _set = panic_cmp.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
    var left = binary_heap.new<Item>()
    var right = binary_heap.new<Item>()
    left.push(new_item(10, 1usize, panic_cmp.retain(), drops.retain()))
    left.push(new_item(5, 2usize, panic_cmp.retain(), drops.retain()))
    left.push(new_item(1, 4usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(9, 8usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(6, 16usize, panic_cmp.retain(), drops.retain()))
    right.push(new_item(2, 32usize, panic_cmp.retain(), drops.retain()))
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
        drops.get().load(core.sync.atomic.Ordering.SeqCst) != 63usize {
        return 7
    }
    0
}
