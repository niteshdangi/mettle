// Array/list conversions, insert_mut, concat/join, PeekMut::pop and exact
// remaining lengths of map, set and sorted-collection iterators.
import alloc.vec
import alloc.vec_deque
import alloc.linked_list
import alloc.hash_map
import alloc.btree
import alloc.binary_heap
import core.iter.{Iterator, ExactSizeIterator, OwnedIterable}

type D { c: ptr<mut i32>; id: i32
    drop { unsafe { *self.c += self.id } } }

fn main(): i32 {
    // Moving an array into a collection neither drops nor duplicates elements.
    var n = 0
    let c = core.ptr.from_mut(n)
    {
        let list: vec.List<D> = ([D(c, 1), D(c, 2), D(c, 4)]).into()
        if n != 0 || list.len() != 3usize { return 1 }
    }
    if n != 7 { return 2 }

    let list: vec.List<i32> = ([1, 2, 3]).into()
    if list.len() != 3usize || list[0usize] != 1 || list[2usize] != 3 { return 3 }
    let no_items: [i32; 0] = []
    let empty: vec.List<i32> = no_items.into()
    if !empty.is_empty() { return 4 }

    let deque: vec_deque.Deque<i32> = ([7, 8]).into()
    if deque.len() != 2usize || deque[1usize] != 8 { return 5 }
    let linked: linked_list.LinkedList<i32> = ([7, 8]).into()
    if linked.len() != 2usize || !linked.contains(8) { return 6 }

    var heap: binary_heap.BinaryHeap<i32> = ([3, 9, 1, 5]).into()
    {
        match heap.peek_mut() {
            present(guard) => { if guard.pop() != 9 { return 7 } },
            none => { return 7 }
        }
    }
    if heap.len() != 3usize { return 8 }
    match heap.peek() { present(v) => { if *v != 5 { return 9 } }, none => { return 9 } }

    var map: hash_map.Map<i32, i32> = ([(1, 10), (2, 20), (1, 30)]).into()
    if map.len() != 2usize { return 10 }
    var keys = map.keys()
    if keys.len() != 2usize { return 11 }
    let first_key = keys.next()
    if keys.len() != 1usize { return 12 }
    var values_mut = map.values_mut()
    if values_mut.len() != 2usize { return 13 }
    let first_value = values_mut.next()
    if values_mut.len() != 1usize { return 14 }

    let set: hash_map.Set<i32> = ([4, 5, 4]).into()
    if set.len() != 2usize { return 15 }
    var owned = set.into_iter()
    if owned.len() != 2usize { return 16 }
    let first_owned = owned.next()
    if owned.len() != 1usize { return 17 }

    var sorted: btree.SortedMap<i32, i32> = ([(3, 30), (1, 10), (2, 20)]).into()
    var sorted_keys = sorted.keys()
    if sorted_keys.len() != 3usize { return 18 }
    let first_sorted = sorted_keys.next()
    if sorted_keys.len() != 2usize { return 19 }
    var sorted_values = sorted.values_mut()
    if sorted_values.len() != 3usize { return 20 }
    let first_sorted_value = sorted_values.next()
    if sorted_values.len() != 2usize { return 21 }
    var sorted_owned = sorted.into_iter()
    if sorted_owned.len() != 3usize { return 22 }
    let first_sorted_owned = sorted_owned.next()
    if sorted_owned.len() != 2usize { return 23 }

    var sorted_set: btree.SortedSet<i32> = ([9, 8, 9]).into()
    if sorted_set.len() != 2usize { return 24 }

    // insert_mut returns the stored slot.
    var items = vec.new<i32>()
    items.push(1)
    items.push(3)
    {
        let slot = items.insert_mut(1usize, 2)
        *slot += 10
    }
    if items.len() != 3usize || items[1usize] != 12 || items[2usize] != 3 { return 25 }

    // concat and join clone the parts and place separators between them only.
    var parts = vec.new<vec.List<i32>>()
    let part_a: vec.List<i32> = ([1, 2]).into()
    let no_part: [i32; 0] = []
    let part_b: vec.List<i32> = no_part.into()
    let part_c: vec.List<i32> = ([3]).into()
    parts.push(part_a)
    parts.push(part_b)
    parts.push(part_c)
    let joined = parts.concat()
    if joined.len() != 3usize || joined[2usize] != 3 { return 26 }
    let separator: vec.List<i32> = ([0]).into()
    let with_separator = parts.join(separator.as_slice())
    if with_separator.len() != 6usize || with_separator[2usize] != 0 || with_separator[3usize] != 0 { return 27 }
    0
}
