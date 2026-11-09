import alloc.binary_heap
import alloc.binary_heap.BinaryHeap
import alloc.btree
import alloc.btree.{SortedMap, SortedSet}
import alloc.hash_map
import alloc.hash_map.{Map, Set}
import alloc.linked_list
import alloc.linked_list.LinkedList
import alloc.vec_deque
import alloc.vec_deque.Deque
import alloc.vec
import alloc.vec.List
import core.clone.Clone
import core.cmp.{Ordering, Ord, PartialOrd}
import core.hash.hash_one
import core.iter.{collect, range, Iterator, MutableIterable, ExtendItems}

fn pairs(from: i32, to: i32): alloc.vec.IntoIter<(i32, i32)> {
    var out = alloc.vec.new<(i32, i32)>()
    var x = from
    while x < to { out.push((x, x * 10)); x += 1 }
    out.into_iter()
}

fn main(): i32 {
    // Deque: wrapped storage still compares by logical order.
    var d1 = vec_deque.new<i32>()
    d1.push_back(2); d1.push_back(3); d1.push_front(1)
    let d2: Deque<i32> = collect(range(1, 4))
    if d1 != d2 || d1.clone() != d2 { return 1 }
    if hash_one(d1) != hash_one(d2) { return 2 }
    let d3: Deque<i32> = collect(range(1, 3))
    if !(d3 < d1) || d1.cmp(read d3) != Ordering.Greater { return 3 }
    for x in mut d1 { *x += 1 }
    if d1[0usize] != 2 || d1[2usize] != 4 || d1 == d2 { return 4 }

    // LinkedList
    var l1 = linked_list.new<i32>()
    l1.push_back(1); l1.push_back(2)
    let l2: LinkedList<i32> = collect(range(1, 3))
    if l1 != l2 || l1.clone() != l2 || hash_one(l1) != hash_one(l2) { return 5 }
    for x in mut l1 { *x *= 5 }
    if l1 == l2 || !(l2 < l1) || l1.cmp(read l2) != Ordering.Greater { return 6 }
    var shorter = linked_list.new<i32>()
    shorter.push_back(5)
    if !(shorter < l1) { return 7 }

    // BinaryHeap
    var h: BinaryHeap<i32> = collect(range(0, 5))
    let hc = h.clone()
    h.push(9)
    if hc.len() != 5usize || h.len() != 6usize { return 8 }
    match h.pop() { present(top) => { if top != 9 { return 9 } }, none => { return 10 } }

    // Map/Set: equality ignores insertion order.
    var m1 = hash_map.new<i32, i32>()
    m1.insert(1, 10); m1.insert(2, 20); m1.insert(3, 30)
    var m2 = hash_map.new<i32, i32>()
    m2.insert(3, 30); m2.insert(1, 10); m2.insert(2, 20)
    if m1 != m2 || m1.clone() != m1 { return 11 }
    let _ = m2.insert(2, 21)
    if m1 == m2 { return 12 }
    var m3 = m1.clone()
    let _ = m3.remove(3)
    if m3 == m1 || m1 == m3 { return 13 }
    for v in mut m1 { *v += 1 }
    match m1.get(2) { present(v) => { if *v != 21 { return 14 } }, none => { return 15 } }
    let m4: Map<i32, i32> = collect(pairs(1, 4))
    if m4.len() != 3usize { return 16 }
    var s1: Set<i32> = collect(range(0, 4))
    var s2 = hash_map.set_new<i32>()
    s2.insert(3); s2.insert(2); s2.insert(1); s2.insert(0)
    if s1 != s2 || s1.clone() != s2 { return 17 }
    s2.insert(9)
    if s1 == s2 || s2 == s1 { return 18 }
    s1.extend(range(0, 6))
    if s1.len() != 6usize { return 19 }

    // SortedMap/SortedSet: ordered comparison and hash.
    let b1: SortedMap<i32, i32> = collect(pairs(1, 3))
    var b2 = b1.clone()
    if b1 != b2 || hash_one(b1) != hash_one(b2) { return 20 }
    for v in mut b2 { *v += 1 }
    if b1 == b2 || !(b1 < b2) || b2.cmp(read b1) != Ordering.Greater { return 21 }
    if hash_one(b1) == hash_one(b2) { return 22 }
    let b3: SortedMap<i32, i32> = collect(pairs(1, 2))
    if !(b3 < b1) { return 23 }
    let t1: SortedSet<i32> = collect(range(1, 4))
    let t2: SortedSet<i32> = collect(range(1, 3))
    if t1 == t2 || t1.clone() != t1 || !(t2 < t1) || hash_one(t1) == hash_one(t2) { return 24 }
    var t3 = t1.clone()
    t3.extend(range(3, 6))
    if t3.len() != 5usize || t3.cmp(read t1) != Ordering.Greater { return 25 }

    var v: List<i32> = collect(range(0, 3))
    v.extend(range(3, 5))
    if v.len() != 5usize { return 26 }
    // collect/extend take any OwnedIterable, including collections directly
    let dup: List<i32> = collect(v)
    var more = vec.new<i32>()
    more.extend(dup)
    if more.len() != 5usize { return 27 }
    let squares: List<i32> = range(0, 4).map(fn(take x: i32): i32 { x * x }).collect()
    if squares.len() != 4usize || squares[3usize] != 9 { return 28 }
    var m = hash_map.new<i32, i32>()
    m.insert(1, 10); m.insert(2, 20)
    var key_sum = 0
    var keys = m.keys()
    while true { match keys.next() { present(k) => { key_sum += *k }, none => { break } } }
    var value_sum = 0
    var values = m.values()
    while true { match values.next() { present(x) => { value_sum += *x }, none => { break } } }
    var tree = btree.new<i32, i32>()
    tree.insert(4, 40); tree.insert(3, 30)
    if key_sum != 3 || value_sum != 30 || tree.keys().count() != 2usize || tree.values().count() != 2usize { return 29 }
    0
}
