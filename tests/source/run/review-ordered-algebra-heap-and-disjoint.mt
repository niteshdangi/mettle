// profiles: debug release
import core.iter.Iterator
import core.ops.DerefMut
import std.panic.CatchResult

fn main(): i32 {
    var left = alloc.btree.set_new<i32>()
    var right = alloc.btree.set_new<i32>()
    let a = left.insert(2)
    let b = left.insert(4)
    let c = right.insert(1)
    let d = right.insert(2)
    let e = right.insert(3)
    var united = left.`union`(read right)
    var expected = 1
    while let present(value) = united.next() {
        if *value != expected { return 1 }
        expected += 1
    }
    if expected != 5 { return 2 }
    var symmetric = left.symmetric_difference(read right)
    if *symmetric.next().or_panic() != 1 || *symmetric.next().or_panic() != 3 ||
        *symmetric.next().or_panic() != 4 || symmetric.next().is_present() { return 3 }
    var common = left.intersection(read right)
    if *common.next().or_panic() != 2 || common.next().is_present() { return 4 }
    var difference = left.difference(read right)
    if *difference.next().or_panic() != 4 || difference.next().is_present() { return 5 }
    var map = alloc.btree.new<i32, i32>()
    let old = map.insert(1, 10)
    let reversed = std.panic.catch_panic(fn(): Unit { let range = map.range(core.iter.range(3, 1)) })
    match take reversed {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 6 }
    }
    let reversed_mut = std.panic.catch_panic(fn(): Unit { let range = map.range_mut(core.iter.range(3, 1)) })
    match take reversed_mut {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 7 }
    }
    var equal = map.range(core.iter.range(1, 1))
    if equal.next().is_present() { return 8 }
    var heap_values = alloc.binary_heap.new<i32>()
    heap_values.push(3)
    heap_values.push(2)
    heap_values.push(1)
    {
        var guard = heap_values.peek_mut().or_panic()
        *guard.deref_mut() = 0
        unsafe { core.mem.forget(take guard) }
    }
    if heap_values.len() != 1usize || *heap_values.peek().or_panic() != 0 { return 9 }
    heap_values.push(5)
    if heap_values.pop().or_panic() != 5 || heap_values.pop().or_panic() != 0 || !heap_values.is_empty() { return 10 }
    heap_values.push(2)
    heap_values.push(5)
    heap_values.push(3)
    {
        var guard = heap_values.peek_mut().or_panic()
        *guard.deref_mut() = 1
    }
    let sorted = heap_values.into_sorted_vec()
    if sorted != [1, 2, 3] { return 11 }
    var hashed = alloc.hash_map.new<i32, i32>()
    let prior = hashed.insert(7, 70)
    let duplicate = std.panic.catch_panic(fn(): Unit { let pair = hashed.get_disjoint_mut(7, 7) })
    match take duplicate {
        CatchResult.Panicked(_) => {},
        CatchResult.Returned(_) => { return 12 }
    }
    if hashed.get_disjoint_mut(7, 8).is_present() { return 13 }
    0
}
