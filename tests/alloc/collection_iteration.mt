import alloc.hash_map;
import alloc.btree;
import alloc.binary_heap;
import alloc.vec_deque;

fn main(): i32 {
    var d = vec_deque.new<i32>()
    d.push_back(2)
    d.push_front(1)
    d.push_back(3)
    var sum = 0
    for x in read d { sum += *x }
    if sum != 6 { return 1 }
    var m = hash_map.new<i32, i32>()
    m.insert(1, 10)
    m.insert(2, 20)
    var ks = 0
    for e in read m { ks += e.value }
    if ks != 30 { return 2 }
    var b = btree.new<i32, i32>()
    b.insert(5, 50)
    b.insert(3, 30)
    var first = 0
    for e in read b { first = e.key
        break }
    if first != 3 { return 3 }
    var h = binary_heap.new<i32>()
    h.push(4)
    h.push(9)
    var hs = 0
    for x in read h { hs += *x }
    if hs != 13 { return 4 }
    var hset = hash_map.set_new<i32>()
    hset.insert(7)
    var c = 0
    for e in read hset { c += e.key }
    if c != 7 { return 5 }
    var bs = btree.set_new<i32>()
    bs.insert(8)
    for e in read bs { c += e.key }
    if c != 15 { return 6 }
    0
}
