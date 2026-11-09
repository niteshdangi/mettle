// profiles: debug release
import alloc.vec
import alloc.vec.List
import alloc.vec_deque
import core.clone.Clone
import core.cmp.{ Eq, PartialEq, Ord, Ordering }
import core.default.Default
import core.iter.{ ExtendItems, FromItems, Iterator, OwnedIterable, BidirectionalIterator }
import core.convert.From

type Counted {
    value: i32
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

fn default_value<T: Default>(): T { T.(Default).default() }

fn same(read deque: vec_deque.Deque<i32>, read expected: [i32]): bool {
    if deque.len() != expected.len() { return false }
    var i = 0usize
    while i < expected.len() {
        if deque[i] != expected[i] { return false }
        i += 1usize
    }
    true
}

fn main(): i32 {
    // Construction, capacity and allocation requests.
    var empty = vec_deque.new<i32>()
    if !empty.is_empty() || empty.len() != 0usize || empty.capacity() != 0usize { return 1 }
    var sized = vec_deque.with_capacity<i32>(4usize)
    if sized.capacity() < 4usize || !sized.is_empty() { return 2 }
    sized.reserve(8usize)
    if sized.capacity() < 8usize { return 3 }
    sized.reserve_exact(2usize)
    match capture sized.try_reserve(3usize) { success(_) => {}, failure(_) => { return 4 } }
    match capture sized.try_reserve_exact(3usize) { success(_) => {}, failure(_) => { return 5 } }
    match capture sized.try_reserve(0xffffffffffffffffusize) { success(_) => { return 6 }, failure(_) => {} }
    sized.shrink_to(0usize)
    if sized.capacity() != 0usize { return 7 }

    // Pushes at both ends, and the element order they produce.
    var d = vec_deque.new<i32>()
    d.push_back(2)
    d.push_front(1)
    d.push_back(3)
    d.push_front(0)
    if !same(d, [0, 1, 2, 3]) { return 10 }
    if d.len() != 4usize || d.is_empty() { return 11 }
    if *d.front().unwrap() != 0 || *d.back().unwrap() != 3 { return 12 }
    if d.get(4usize).is_present() || *d.get(1usize).unwrap() != 1 { return 13 }
    match take d.back_mut() {
        present(last) => { *last = 30 },
        none => { return 14 }
    }
    match take d.front_mut() {
        present(first) => { *first = 10 },
        none => { return 15 }
    }
    match take d.get_mut(2usize) {
        present(slot) => { *slot = 20 },
        none => { return 16 }
    }
    if !same(d, [10, 1, 20, 30]) { return 17 }
    {
        let last = d.push_back_mut(40)
        *last = 41
        let first = d.push_front_mut(9)
        *first = 8
    }
    if !same(d, [8, 10, 1, 20, 30, 41]) { return 18 }

    // Pops from either end, and the conditional pops.
    match d.pop_front() {
        present(value) => { if value != 8 { return 20 } },
        none => { return 21 }
    }
    match d.pop_back() {
        present(value) => { if value != 41 { return 22 } },
        none => { return 23 }
    }
    match d.pop_front_if(fn(mut value: i32): bool { value == 10 }) {
        present(value) => { if value != 10 { return 24 } },
        none => { return 25 }
    }
    if d.pop_front_if(fn(mut value: i32): bool { value == 99 }).is_present() { return 26 }
    if d.pop_back_if(fn(mut value: i32): bool { value == 99 }).is_present() { return 27 }
    match d.pop_back_if(fn(mut value: i32): bool { value == 30 }) {
        present(value) => { if value != 30 { return 28 } },
        none => { return 29 }
    }
    if !same(d, [1, 20]) { return 30 }

    // Positional insert, remove and the swap family.
    d.insert(1usize, 5)
    if !same(d, [1, 5, 20]) { return 31 }
    {
        let inserted = d.insert_mut(2usize, 6)
        *inserted = 7
    }
    if !same(d, [1, 5, 7, 20]) { return 32 }
    if d.remove(2usize) != 7 || !same(d, [1, 5, 20]) { return 33 }
    if d.swap_remove_back(0usize) != 1 || !same(d, [20, 5]) { return 34 }
    d.push_front(4)
    if d.swap_remove_front(2usize) != 5 || !same(d, [20, 4]) { return 35 }
    d.push_back(9)
    d.swap(0usize, 2usize)
    if !same(d, [9, 4, 20]) { return 36 }

    // Rotation and slice views, including a wrapped ring.
    d.rotate_left(1usize)
    if !same(d, [4, 20, 9]) { return 40 }
    d.rotate_right(2usize)
    if !same(d, [20, 9, 4]) { return 41 }
    let (first, second) = d.as_slices()
    if first.len() + second.len() != 3usize { return 42 }
    {
        let (first_mut, second_mut) = d.as_mut_slices()
        if first_mut.len() + second_mut.len() != 3usize { return 43 }
    }
    let contiguous = d.make_contiguous()
    if contiguous.len() != 3usize || contiguous[0usize] != 20 { return 44 }

    // Searches over the ordered deque.
    var ordered = vec_deque.new<i32>()
    ordered.push_back(1)
    ordered.push_back(3)
    ordered.push_back(5)
    ordered.push_back(7)
    match capture ordered.binary_search(5) {
        success(index) => { if index != 2usize { return 50 } },
        failure(_) => { return 51 }
    }
    match capture ordered.binary_search(4) {
        success(_) => { return 52 },
        failure(index) => { if index != 2usize { return 53 } }
    }
    match capture ordered.binary_search_by(fn(read value: i32): Ordering { value.cmp(7) }) {
        success(index) => { if index != 3usize { return 54 } },
        failure(_) => { return 55 }
    }
    match capture ordered.binary_search_by_key(9, fn(read value: i32): i32 { value + 4 }) {
        success(index) => { if index != 2usize { return 56 } },
        failure(_) => { return 57 }
    }
    if ordered.partition_point(fn(read value: i32): bool { value < 6 }) != 3usize { return 58 }
    if !ordered.contains(3) || ordered.contains(4) { return 59 }

    // Ranges, drains and iterators.
    var sum = 0
    for value in ordered.range(1usize, 3usize) { sum += *value }
    if sum != 8 { return 60 }
    {
        var range = ordered.range_mut(0usize, 2usize)
        match take range.next() {
            present(value) => { *value = 100 },
            none => { return 61 }
        }
        match take range.next_back() {
            present(value) => { *value = 300 },
            none => { return 62 }
        }
        if range.next().is_present() { return 63 }
    }
    if !same(ordered, [100, 300, 5, 7]) { return 64 }
    var mutable_sum = 0
    {
        var it = ordered.iter_mut()
        match take it.next_back() {
            present(value) => { *value += 1 },
            none => { return 65 }
        }
    }
    for value in ordered.iter_mut() { *value += 1 }
    if !same(ordered, [101, 301, 6, 9]) { return 66 }
    for value in read ordered { mutable_sum += *value }
    if mutable_sum != 417 { return 67 }
    var backward = 0
    var reverse = ordered.iter()
    match take reverse.next_back() {
        present(value) => { backward = *value },
        none => { return 68 }
    }
    if backward != 9 || reverse.size_hint() != (3usize, present(3usize)) { return 69 }

    var drained = vec_deque.new<i32>()
    drained.push_back(1)
    drained.push_back(2)
    drained.push_back(3)
    drained.push_back(4)
    var removed = 0
    {
        var drain = drained.drain(1usize..3usize)
        match take drain.next() {
            present(value) => { removed += value },
            none => { return 70 }
        }
        match take drain.next_back() {
            present(value) => { removed += value * 10 },
            none => { return 71 }
        }
    }
    if removed != 32 || !same(drained, [1, 4]) { return 72 }
    {
        var all = drained.drain(0usize..2usize)
        if all.size_hint() != (2usize, present(2usize)) { return 73 }
    }
    if !drained.is_empty() { return 74 }

    // Growth-changing edits: append, split_off, resize and truncate.
    var left = vec_deque.new<i32>()
    left.push_back(1)
    left.push_back(2)
    var right = vec_deque.new<i32>()
    right.push_back(3)
    right.push_back(4)
    left.append(mut right)
    if !same(left, [1, 2, 3, 4]) || !right.is_empty() { return 80 }
    var tail = left.split_off(2usize)
    if !same(left, [1, 2]) || !same(tail, [3, 4]) { return 81 }
    left.resize(4usize, 7)
    if !same(left, [1, 2, 7, 7]) { return 82 }
    left.resize(1usize, 0)
    if !same(left, [1]) { return 83 }
    left.resize_with(3usize, fn(): i32 { 5 })
    if !same(left, [1, 5, 5]) { return 84 }
    left.truncate(2usize)
    if !same(left, [1, 5]) { return 85 }
    left.retain_back(1usize)
    if !same(left, [5]) { return 86 }
    left.clear()
    if !left.is_empty() { return 87 }

    // Retain with stateful callbacks.
    var kept = vec_deque.new<i32>()
    var i = 0
    while i < 6 {
        kept.push_back(i + 0)
        i += 1
    }
    var seen = 0
    kept.retain(fn(read value: i32): bool {
        seen += 1
        value % 2 == 0
    })
    if seen != 6 || !same(kept, [0, 2, 4]) { return 90 }
    kept.retain_mut(fn(mut value: i32): bool {
        value += 1
        value != 3
    })
    if !same(kept, [1, 5]) { return 91 }

    // Traits: Clone, comparisons, Default, Index and conversions.
    let cloned = kept.clone()
    if !same(cloned, [1, 5]) || cloned != kept { return 100 }
    var other = vec_deque.new<i32>()
    other.push_back(1)
    other.push_back(6)
    if kept == other || !(kept < other) || kept.cmp(other) != Ordering.Less { return 101 }
    let defaulted: vec_deque.Deque<i32> = default_value<vec_deque.Deque<i32>>()
    if !defaulted.is_empty() { return 102 }
    kept[0usize] = 11
    if kept[0usize] != 11 { return 103 }
    let plain = List<i32>.(From<vec_deque.Deque<i32>>).from(kept)
    if plain.len() != 2usize || plain[1usize] != 5 { return 104 }

    var source = vec.new<i32>()
    source.push(3)
    source.push(2)
    source.push(1)
    let collected = vec_deque.Deque<i32>.(FromItems<i32>).from_iter(source)
    if !same(collected, [3, 2, 1]) { return 105 }
    var extended = vec_deque.new<i32>()
    var more = vec.new<i32>()
    more.push(8)
    more.push(9)
    extended.extend(more)
    if !same(extended, [8, 9]) { return 106 }

    // Owned iteration drops what it has not yet yielded.
    var drops = 0usize
    {
        var owned = vec_deque.new<Counted>()
        owned.push_back(Counted(1, core.ptr.from_mut(drops)))
        owned.push_back(Counted(2, core.ptr.from_mut(drops)))
        owned.push_back(Counted(3, core.ptr.from_mut(drops)))
        match take owned.into_iter().next() {
            present(item) => { if item.value != 1 { return 110 } },
            none => { return 111 }
        }
    }
    if drops != 3usize { return 112 }
    0
}
