import alloc.btree
import alloc.binary_heap
import alloc.vec
import alloc.vec_deque
import alloc.hash_map
import core.iter.{Iterator, ExactSizeIterator}
import core.default.Default

fn make<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    var map = btree.new<i32, i32>()
    map.insert(1, 10)
    map.insert(2, 20)
    if map[2] != 20 { return 1 }

    var heap = binary_heap.new<i32>()
    heap.push(3)
    heap.push(9)
    heap.push(5)
    {
        var sorted = heap.drain_sorted()
        if sorted.len() != 3usize { return 2 }
        if sorted.next().unwrap() != 9 { return 3 }
        if sorted.next().unwrap() != 5 { return 4 }
    }
    if !heap.is_empty() { return 5 }

    heap.push(1)
    heap.push(7)
    var rest = heap.into_iter_sorted()
    if rest.next().unwrap() != 7 { return 6 }
    if rest.next().unwrap() != 1 { return 7 }
    if !rest.next().is_none() { return 8 }

    var empty: hash_map.MapIntoIter<i32, i32> = make()
    if !empty.next().is_none() { return 9 }
    var none_left: vec_deque.DequeIntoIter<i32> = make()
    if !none_left.next().is_none() { return 10 }

    var list = vec.new<i32>()
    list.push(1)
    list.push(2)
    list.push(3)
    match list.get_disjoint_mut<2usize>([0usize, 2usize]) {
        present(parts) => {
            let tmp = *parts[0usize]
            *parts[0usize] = *parts[1usize]
            *parts[1usize] = tmp
        },
        none => { return 11 }
    }
    if list[0usize] != 3 || list[2usize] != 1 { return 12 }
    if !list.get_disjoint_mut<2usize>([1usize, 1usize]).is_none() { return 13 }
    0
}
