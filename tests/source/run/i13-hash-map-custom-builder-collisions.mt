// Custom map and set builders govern lookup, insertion, and deletion.
import alloc.hash_map.{Map, Set}
import alloc.binary_heap.BinaryHeap
import alloc.btree.{SortedMap, SortedSet}
import alloc.vec_deque.Deque
import alloc.alloc.Global
import core.hash.{BuildHasher, Hasher}
import core.default.Default
import core.clone.Clone
import core.iter.Iterator

type CollisionHasher {}
extend CollisionHasher implements Hasher {
    mut fn write(bytes: read [u8]): Unit {}
    fn finish(): u64 { 0u64 }
}
type CollisionBuilder {}
extend CollisionBuilder implements BuildHasher {
    type Hasher = CollisionHasher
    fn build_hasher(): CollisionHasher { CollisionHasher() }
}
extend CollisionBuilder implements Clone {
    fn clone(): CollisionBuilder { CollisionBuilder() }
}

type SeededHasher { state: u64 }
extend SeededHasher implements Hasher {
    mut fn write(bytes: read [u8]): Unit {
        var i = 0usize
        while i < bytes.len() {
            self.state = self.state.rotate_left(5u32) ^ (bytes[i] as u64)
            i += 1usize
        }
    }
    fn finish(): u64 { self.state }
}
type SeededBuilder { seed: u64 }
extend SeededBuilder implements BuildHasher {
    type Hasher = SeededHasher
    fn build_hasher(): SeededHasher { SeededHasher(self.seed) }
}
extend SeededBuilder implements Clone {
    fn clone(): SeededBuilder { SeededBuilder(self.seed) }
}

fn main(): i32 {
    var map = Map<i32, i32, Global, CollisionBuilder>.with_capacity_and_hasher(
        4usize,
        CollisionBuilder()
    )
    if map.capacity() < 4usize { return 1 }
    let _ = map.insert(1, 10)
    let _ = map.insert(2, 20)
    let _ = map.insert(3, 30)
    match map.get(3) {
        present(value) => { if *value != 30 { return 2 } },
        none => { return 2 }
    }
    match map.remove(2) {
        present(value) => { if value != 20 { return 3 } },
        none => { return 3 }
    }
    match map.get(3) {
        present(value) => { if *value != 30 { return 4 } },
        none => { return 4 }
    }
    if map[3] != 30 { return 19 }
    let entry = map.entry(4).or_insert_with_key(fn(key: read i32): i32 { *key * 10 })
    if *entry != 40 { return 5 }

    var built = Map<i32, i32, Global, CollisionBuilder>.with_hasher(CollisionBuilder())
    let _ = built.insert(8, 80)
    if built.len() != 1usize { return 6 }
    let copied = map.clone()
    match copied.get(4) {
        present(value) => { if *value != 40 { return 7 } },
        none => { return 7 }
    }
    var map_keys = copied.into_keys()
    var key_sum = 0
    while true {
        match map_keys.next() {
            present(key) => { key_sum += key },
            none => { break }
        }
    }
    if key_sum != 8 { return 21 }

    var set = Set<i32, Global, CollisionBuilder>.with_capacity_and_hasher(
        3usize,
        CollisionBuilder()
    )
    if set.capacity() < 3usize { return 8 }
    if !set.insert(1) || !set.insert(2) || !set.insert(3) || set.insert(2) {
        return 9
    }
    match set.get(3) {
        present(value) => { if *value != 3 { return 10 } },
        none => { return 10 }
    }
    if !set.remove(2) || set.contains(2) || !set.contains(3) { return 11 }
    var built_set = Set<i32, Global, CollisionBuilder>.with_hasher(CollisionBuilder())
    if !built_set.insert(11) || !built_set.contains(11) { return 12 }
    var set_iter = built_set.into_iter()
    match set_iter.next() {
        present(key) => { if key != 11 { return 22 } },
        none => { return 22 }
    }

    let default_map = Map<i32, i32>.(Default).default()
    if !default_map.is_empty() { return 13 }
    let default_set = Set<i32>.(Default).default()
    if !default_set.is_empty() { return 14 }
    let default_heap = BinaryHeap<i32>.(Default).default()
    if !default_heap.is_empty() { return 23 }
    let default_deque = Deque<i32>.(Default).default()
    if !default_deque.is_empty() { return 24 }
    let default_sorted_map = SortedMap<i32, i32>.(Default).default()
    if !default_sorted_map.is_empty() { return 25 }
    let default_sorted_set = SortedSet<i32>.(Default).default()
    if !default_sorted_set.is_empty() { return 26 }

    var seeded = Map<i32, i32, Global, SeededBuilder>.with_hasher(SeededBuilder(42u64))
    let _ = seeded.insert(12, 120)
    if seeded.hasher().seed != 42u64 { return 15 }
    match seeded.get(12) {
        present(value) => { if *value != 120 { return 16 } },
        none => { return 16 }
    }
    let seeded_copy = seeded.clone()
    if seeded_copy.hasher().seed != 42u64 { return 17 }
    match seeded_copy.get(12) {
        present(value) => { if *value != 120 { return 18 } },
        none => { return 18 }
    }
    var seed_again = Map<i32, i32, Global, SeededBuilder>.with_hasher(SeededBuilder(999u64))
    let _ = seed_again.insert(1, 10)
    let _ = seed_again.insert(3, 30)
    let _ = seed_again.insert(4, 40)
    let _ = set.insert(4)
    var mixed_set = Set<i32, Global, SeededBuilder>.with_hasher(SeededBuilder(17u64))
    if mixed_set.hasher().seed != 17u64 { return 30 }
    let _ = mixed_set.insert(1)
    let _ = mixed_set.insert(3)
    let _ = mixed_set.insert(4)
    if !set.eq(mixed_set) { return 27 }
    var mixed_union = set.union(mixed_set)
    var union_count = 0usize
    while true {
        match mixed_union.next() {
            present(_) => { union_count += 1usize },
            none => { break }
        }
    }
    if union_count != 3usize { return 28 }
    if !map.eq(seed_again) { return 29 }
    0
}
