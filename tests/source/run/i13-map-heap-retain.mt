// Map and set retain, plus heap append and retain, including drop counts.
import alloc.binary_heap
import alloc.binary_heap.BinaryHeap
import alloc.hash_map
import alloc.hash_map.{Map, Set}
import core.cmp.{Eq, Ord, Ordering, PartialEq, PartialOrd}

type DropCount {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

type HeapItem {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}
extend HeapItem implements PartialEq {
    fn eq(other: read HeapItem): bool { self.value == other.value }
}
extend HeapItem implements Eq {}
extend HeapItem implements PartialOrd {
    fn partial_cmp(other: read HeapItem): Ordering? { present(self.value.cmp(read other.value)) }
}
extend HeapItem implements Ord {
    fn cmp(other: read HeapItem): Ordering { self.value.cmp(read other.value) }
}

fn main(): i32 {
    let sized = Map<i32, i32>.with_capacity(8usize)
    if sized.capacity() < 8usize { return 1 }
    let sized_set = Set<i32>.with_capacity(8usize)
    if sized_set.capacity() < 8usize { return 2 }

    var map = hash_map.new<i32, i32>()
    let _ = map.insert(1, 10)
    let _ = map.insert(2, 20)
    let _ = map.insert(3, 30)
    map.retain(fn(key: read i32, value: mut i32): bool {
        if key == 1 { *value = 11 }
        key != 2
    })
    if map.len() != 2usize || map.contains_key(2) { return 3 }
    match map.get(1) {
        present(value) => { if *value != 11 { return 4 } },
        none => { return 4 }
    }
    match map.get(3) {
        present(value) => { if *value != 30 { return 5 } },
        none => { return 5 }
    }

    var drops = 0
    {
        var owned = hash_map.new<i32, DropCount>()
        let _ = owned.insert(1, DropCount(core.ptr.from_mut(drops)))
        let _ = owned.insert(2, DropCount(core.ptr.from_mut(drops)))
        let _ = owned.insert(4, DropCount(core.ptr.from_mut(drops)))
        owned.retain(fn(key: read i32, value: mut DropCount): bool { key == 2 })
        if owned.len() != 1usize || drops != 2 { return 6 }
    }
    if drops != 3 { return 7 }

    var set = hash_map.set_new<i32>()
    if !set.insert(1) || !set.insert(2) || !set.insert(3) { return 8 }
    set.retain(fn(key: read i32): bool { key != 2 })
    if set.len() != 2usize || !set.contains(1) || set.contains(2) || !set.contains(3) {
        return 9
    }

    var heap = BinaryHeap<i32>.with_capacity(4usize)
    if heap.capacity() < 4usize { return 10 }
    heap.push(1)
    heap.push(5)
    heap.push(3)
    var extra = binary_heap.new<i32>()
    extra.push(9)
    extra.push(2)
    heap.append(mut extra)
    if extra.len() != 0usize || heap.len() != 5usize { return 11 }
    match heap.pop() { present(value) => { if value != 9 { return 12 } }, none => { return 12 } }
    match heap.pop() { present(value) => { if value != 5 { return 13 } }, none => { return 13 } }
    match heap.pop() { present(value) => { if value != 3 { return 14 } }, none => { return 14 } }
    match heap.pop() { present(value) => { if value != 2 { return 15 } }, none => { return 15 } }
    match heap.pop() { present(value) => { if value != 1 { return 16 } }, none => { return 16 } }

    var filtered = binary_heap.new<i32>()
    filtered.push(1)
    filtered.push(4)
    filtered.push(2)
    filtered.push(5)
    filtered.push(3)
    filtered.retain(fn(value: read i32): bool { value >= 3 })
    if filtered.len() != 3usize { return 17 }
    match filtered.pop() { present(value) => { if value != 5 { return 18 } }, none => { return 18 } }
    match filtered.pop() { present(value) => { if value != 4 { return 19 } }, none => { return 19 } }
    match filtered.pop() { present(value) => { if value != 3 { return 20 } }, none => { return 20 } }

    var heap_drops = 0
    {
        var owned = binary_heap.new<HeapItem>()
        let counter = core.ptr.from_mut(heap_drops)
        owned.push(HeapItem(counter, 1))
        owned.push(HeapItem(counter, 3))
        owned.push(HeapItem(counter, 2))
        owned.retain(fn(item: read HeapItem): bool { item.value >= 2 })
        if owned.len() != 2usize || heap_drops != 1 { return 21 }
        match owned.pop() {
            present(item) => { if item.value != 3 { return 22 } },
            none => { return 22 }
        }
        match owned.pop() {
            present(item) => { if item.value != 2 { return 23 } },
            none => { return 23 }
        }
    }
    if heap_drops != 3 { return 24 }
    0
}
