// profiles: debug release
import alloc.binary_heap
import alloc.btree
import alloc.hash_map
import alloc.string
import alloc.string.String
import alloc.vec.List
import alloc.vec_deque
import core.borrow.{OwnedType, ToOwned}
import core.clone.Clone
import core.convert.From
import core.fmt
import core.iter.{ExactSizeIterator, Iterator, OwnedIterable}

fn render<T: fmt.Debug>(read value: T): String throws fmt.Error {
    var out = string.new()
    {
        var formatter = fmt.formatter(mut out, fmt.spec())
        try value.fmt(mut formatter)
    }
    out
}

fn rejects_full_writer<T: fmt.Debug>(read value: T): bool {
    var buffer: [u8; 0] = []
    var out = fmt.buffer_writer(mut buffer)
    var formatter = fmt.formatter(mut out, fmt.spec())
    match capture value.fmt(mut formatter) {
        success(_) => false,
        failure(_) => true
    }
}

fn cloned<I: Iterator + Clone + OwnedType<Owned = I> + ToOwned + fmt.Debug>(
    take source: I
): Unit throws fmt.Error {
    var original = source
    let _ = original.next()
    var duplicate = original.clone()
    var owned: I = original.to_owned()
    let snapshot = try render(original)
    assert(snapshot.as_text().contains("7"), "remaining iterator payloads are formatted")
    assert(try render(duplicate) == snapshot, "clone preserves formatted remaining state")
    assert(try render(owned) == snapshot, "ToOwned preserves formatted remaining state")
    assert(rejects_full_writer(original), "iterator formatting propagates writer failure")
    var remaining = 0usize
    while original.next().is_present() { remaining += 1usize }
    assert(remaining == 2usize && duplicate.count() == remaining && owned.count() == remaining,
        "original, clone and owned cursors advance independently")
    let empty = try render(original)
    assert(!empty.as_text().contains("7"), "exhausted iterator formats no old payload")
}

fn formatted<I: Iterator + ExactSizeIterator + fmt.Debug>(take source: I): Unit throws fmt.Error {
    var items = source
    let before = items.len()
    let snapshot = try render(items)
    assert(snapshot.as_text().contains("7"), "iterator formatting visits payloads")
    assert(items.len() == before, "formatting does not advance the iterator")
    assert(rejects_full_writer(items), "formatting propagates writer failure")
    let _ = items.next()
    let tail = try render(items)
    assert(items.len() == before - 1usize && snapshot != tail,
        "formatting follows the remaining cursor")
    while items.next().is_present() {}
    let empty = try render(items)
    assert(!empty.as_text().contains("7"), "exhausted iterator formats no payload")
}

fn run(): Unit throws fmt.Error {
    let numbers = [7, 77, 777]
    let pairs = [(7, 7), (77, 77), (777, 777)]
    var list = List<i32>.(From<[i32; 3]>).from(numbers.clone())
    try cloned(list.clone().into_iter())
    try formatted(list.drain(0usize..3usize))
    var queue = binary_heap.BinaryHeap<i32>.(From<[i32; 3]>).from(numbers.clone())
    try cloned(queue.iter())
    try cloned(queue.clone().into_iter())
    try formatted(queue.drain())
    var deque = vec_deque.Deque<i32>.(From<[i32; 3]>).from(numbers.clone())
    try cloned(deque.iter())
    try cloned(deque.clone().into_iter())
    try formatted(deque.iter_mut())
    try formatted(deque.drain(0usize..3usize))
    var map = hash_map.Map<i32, i32>.(From<[(i32, i32); 3]>).from(pairs.clone())
    try cloned(map.iter())
    try cloned(map.keys())
    try cloned(map.values())
    try formatted(map.iter_mut())
    try formatted(map.clone().into_iter())
    {
        let occupied = try render(map.entry(7))
        assert(occupied.as_text().contains("7"), "occupied entry formats its key")
    }
    {
        let vacant = try render(map.entry(7777))
        assert(vacant.as_text().contains("7777"), "vacant entry formats pending key")
    }
    try formatted(map.drain())
    var tree = btree.SortedMap<i32, i32>.(From<[(i32, i32); 3]>).from(pairs)
    try cloned(tree.iter())
    try cloned(tree.keys())
    try cloned(tree.values())
    try formatted(tree.iter_mut())
    try formatted(tree.clone().into_iter())
    {
        let occupied = try render(tree.entry(7))
        assert(occupied.as_text().contains("7"), "occupied tree entry formats key")
    }
    {
        let vacant = try render(tree.entry(7777))
        assert(vacant.as_text().contains("7777"), "vacant tree entry formats pending key")
    }
    var set = hash_map.Set<i32>.(From<[i32; 3]>).from(numbers.clone())
    try cloned(set.iter())
    try formatted(set.clone().into_iter())
    try formatted(set.drain())
    let sorted = btree.SortedSet<i32>.(From<[i32; 3]>).from(numbers)
    try cloned(sorted.iter())
    try formatted(sorted.clone().into_iter())
}

fn main(): i32 {
    match capture run() { success(_) => 0, failure(_) => 1 }
}
