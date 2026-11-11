// profiles: debug release
import alloc.binary_heap
import alloc.vec
import alloc.vec.List
import core.clone.Clone
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.iter.{BidirectionalIterator, ExactSizeIterator, ExtendItems, FromItems, Iterator, OwnedIterable}
import core.ops.DerefMut

fn heap_values(read queue: binary_heap.BinaryHeap<i32>): i32 {
    var sum = 0
    for value in queue.iter() { sum += *value }
    sum
}

fn default_value<T: Default>(): T { T.(Default).default() }
fn require_debug<T: Debug>(read value: T): bool { true }
fn exact_len<I: ExactSizeIterator>(read items: I): usize {
    I.(ExactSizeIterator).len(items)
}

fn check_iter<region r>(
    read queue: binary_heap.BinaryHeap<i32> from r
): bool {
    if !require_debug(read queue) { return false }
    var empty: binary_heap.Iter<region r, i32> =
        default_value<binary_heap.Iter<region r, i32>>()
    var empty_copy = empty.clone()
    if !require_debug(read empty) ||
        empty.size_hint() != (0usize, present(0usize)) ||
        exact_len(read empty) != 0usize ||
        empty.next().is_present() ||
        empty_copy.next_back().is_present() {
        return false
    }
    var forward = queue.iter()
    var backward = forward.clone()
    if !require_debug(read forward) ||
        exact_len(read forward) != queue.len() {
        return false
    }
    var forward_count = 0usize
    var forward_sum = 0i32
    while true {
        match forward.next() {
            present(value) => { forward_count += 1usize; forward_sum += *value },
            none => { break }
        }
    }
    var backward_count = 0usize
    var backward_sum = 0i32
    while true {
        match backward.next_back() {
            present(value) => { backward_count += 1usize; backward_sum += *value },
            none => { break }
        }
    }
    forward_count == queue.len() &&
        backward_count == queue.len() &&
        forward_sum == backward_sum &&
        exact_len(read forward) == 0usize
}

fn main(): i32 {
    // Construction, capacity and allocation requests.
    var empty = binary_heap.new<i32>()
    if !empty.is_empty() || empty.len() != 0usize { return 1 }
    if empty.peek().is_present() || empty.pop().is_present() { return 2 }
    var defaulted: binary_heap.BinaryHeap<i32> = default_value<binary_heap.BinaryHeap<i32>>()
    if !defaulted.is_empty() { return 3 }
    var queue = binary_heap.with_capacity<i32>(4usize)
    if queue.capacity() < 4usize { return 4 }
    queue.reserve(10usize)
    if queue.capacity() < 10usize { return 5 }
    queue.reserve_exact(2usize)
    match capture queue.try_reserve(3usize) { success(_) => {}, failure(_) => { return 6 } }
    match capture queue.try_reserve_exact(3usize) { success(_) => {}, failure(_) => { return 7 } }
    match capture queue.try_reserve(0xffffffffffffffffusize) { success(_) => { return 8 }, failure(_) => {} }
    queue.shrink_to(0usize)

    // Pushes keep the maximum at the front.
    queue.push(3)
    queue.push(9)
    queue.push(1)
    queue.push(7)
    if queue.len() != 4usize || queue.is_empty() { return 10 }
    if !check_iter(read queue) { return 43 }
    if *queue.peek().unwrap() != 9 { return 11 }
    if heap_values(read queue) != 20 { return 12 }
    if queue.as_slice().len() != 4usize { return 13 }
    let before_shrink = queue.capacity()
    queue.shrink_to_fit()
    if queue.capacity() < 4usize || queue.capacity() > before_shrink ||
        queue.len() != 4usize { return 14 }

    // Pops come out largest first.
    match queue.pop() {
        present(value) => { if value != 9 { return 15 } },
        none => { return 16 }
    }
    if *queue.peek().unwrap() != 7 { return 17 }
    match queue.pop() {
        present(value) => { if value != 7 { return 18 } },
        none => { return 19 }
    }
    match queue.pop() {
        present(value) => { if value != 3 { return 20 } },
        none => { return 21 }
    }
    match queue.pop() {
        present(value) => { if value != 1 { return 22 } },
        none => { return 23 }
    }
    if queue.pop().is_present() || !queue.is_empty() { return 24 }

    // peek_mut writes are restored to queue order when the guard drops.
    var mutable = binary_heap.new<i32>()
    mutable.push(5)
    mutable.push(2)
    mutable.push(8)
    {
        match take mutable.peek_mut() {
            present(top) => {
                var guard = take top
                let slot = guard.deref_mut()
                *slot = 1
            },
            none => { return 25 }
        }
    }
    if *mutable.peek().unwrap() != 5 { return 26 }
    if binary_heap.new<i32>().peek_mut().is_present() { return 27 }

    // Sorted and unsorted extraction.
    var sorted_source = binary_heap.new<i32>()
    sorted_source.push(4)
    sorted_source.push(1)
    sorted_source.push(6)
    sorted_source.push(2)
    let sorted = sorted_source.into_sorted_vec()
    if sorted.len() != 4usize || sorted[0usize] != 1 || sorted[3usize] != 6 { return 28 }

    var pool = binary_heap.new<i32>()
    pool.push(10)
    pool.push(20)
    pool.push(30)
    let raw = pool.into_vec()
    if raw.len() != 3usize { return 29 }
    var kept = binary_heap.new<i32>()
    kept.push(4)
    kept.push(8)
    kept.push(6)
    let ascending = kept.into_sorted_vec()
    if ascending.len() != 3usize || ascending[0usize] != 4 ||
        ascending[1usize] != 6 || ascending[2usize] != 8 { return 30 }
    let from_array = binary_heap.BinaryHeap<i32>.(From<[i32; 4]>).from([3, 1, 4, 2])
    if from_array.len() != 4usize || *from_array.peek().unwrap() != 4 { return 31 }
    var arbitrary = vec.new<i32>()
    arbitrary.push(1)
    arbitrary.push(4)
    arbitrary.push(2)
    arbitrary.push(3)
    var from_list = binary_heap.BinaryHeap<i32>.(From<List<i32>>).from(arbitrary)
    if *from_list.peek().unwrap() != 4 || from_list.len() != 4usize { return 32 }
    if from_list.pop().unwrap() != 4 || from_list.pop().unwrap() != 3 ||
        from_list.pop().unwrap() != 2 || from_list.pop().unwrap() != 1 {
        return 33
    }

    // Retain and append keep only the surviving values in queue order.
    var retained = binary_heap.new<i32>()
    var i = 0
    while i < 8 {
        retained.push(i + 0)
        i += 1
    }
    var visits = 0
    retained.retain(fn(read value: i32): bool {
        visits += 1
        value % 2 == 0
    })
    if visits != 8 || retained.len() != 4usize || *retained.peek().unwrap() != 6 { return 34 }

    var left = binary_heap.new<i32>()
    left.push(1)
    left.push(5)
    var right = binary_heap.new<i32>()
    right.push(9)
    right.push(3)
    left.append(mut right)
    if !right.is_empty() || left.len() != 4usize || *left.peek().unwrap() != 9 { return 35 }

    // Draining and clearing.
    var drained_sum = 0
    {
        var drain = left.drain()
        if !require_debug(read drain) || exact_len(read drain) != 4usize { return 44 }
        match drain.next_back() {
            present(value) => { drained_sum += value },
            none => { return 45 }
        }
        while true {
            match drain.next() {
                present(value) => { drained_sum += value },
                none => { break }
            }
        }
    }
    if drained_sum != 18 || !left.is_empty() { return 36 }
    left.push(2)
    left.clear()
    if !left.is_empty() { return 37 }

    // Traits: From, FromItems, ExtendItems, OwnedIterable and Clone.
    var source = vec.new<i32>()
    source.push(2)
    source.push(7)
    source.push(4)
    let from_list = binary_heap.BinaryHeap<i32>.(FromItems<i32>).from_iter(source)
    if *from_list.peek().unwrap() != 7 || from_list.len() != 3usize { return 38 }
    var more = vec.new<i32>()
    more.push(11)
    more.push(1)
    var grown = binary_heap.new<i32>()
    grown.extend(more)
    if *grown.peek().unwrap() != 11 || grown.len() != 2usize { return 39 }
    let duplicate = grown.clone()
    if duplicate.len() != 2usize || *duplicate.peek().unwrap() != 11 { return 40 }
    let back = List<i32>.(From<binary_heap.BinaryHeap<i32>>).from(duplicate)
    if back.len() != 2usize { return 41 }
    var empty_owned: vec.IntoIter<i32> = default_value<vec.IntoIter<i32>>()
    if !require_debug(read empty_owned) ||
        empty_owned.size_hint() != (0usize, present(0usize)) ||
        exact_len(read empty_owned) != 0usize {
        return 46
    }
    var owned = from_list.into_iter()
    var copied = owned.clone()
    if !require_debug(read owned) || exact_len(read owned) != 3usize { return 47 }
    var owned_sum = 0
    while true {
        match owned.next() {
            present(value) => { owned_sum += value },
            none => { break }
        }
    }
    var copied_sum = 0
    while true {
        match copied.next_back() {
            present(value) => { copied_sum += value },
            none => { break }
        }
    }
    if owned_sum != 13 || copied_sum != 13 || exact_len(read owned) != 0usize {
        return 42
    }
    0
}
