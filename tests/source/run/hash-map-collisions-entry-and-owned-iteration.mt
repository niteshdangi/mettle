import alloc.hash_map
import core.hash.{Hash, Hasher}

type CollisionKey { value: i32 }

extend CollisionKey implements PartialEq {
    fn eq(other: read CollisionKey): bool { self.value == other.value }
}

extend CollisionKey implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u64(0u64) }
}

fn main(): i32 {
    var map = hash_map.new<CollisionKey, i32>()
    var i = 0i32
    while i < 25i32 {
        let old = map.insert(CollisionKey(i), i * 10)
        i += 1i32
    }

    let existing = map.entry(CollisionKey(7i32)).or_insert(700)
    *existing = 71
    let inserted = map.entry(CollisionKey(30i32)).or_insert(300)
    *inserted = 300

    match map.remove(CollisionKey(10i32)) {
        present(value) => { if value != 100 { return 1 } },
        none => { return 2 }
    }
    match map.get(CollisionKey(20i32)) {
        present(value) => { if *value != 200 { return 3 } },
        none => { return 4 }
    }

    var total = 0i32
    for pair in take map { total += pair.1 }
    if total != 3201i32 { return 5 }

    var set = hash_map.set_new<CollisionKey>()
    if !set.insert(CollisionKey(1i32)) { return 6 }
    if !set.insert(CollisionKey(2i32)) { return 7 }
    if set.insert(CollisionKey(1i32)) { return 8 }
    if !set.remove(CollisionKey(1i32)) || !set.contains(CollisionKey(2i32)) { return 9 }
    var set_sum = 0i32
    for item in take set { set_sum += item.value }
    if set_sum != 2i32 { return 10 }
    0
}
