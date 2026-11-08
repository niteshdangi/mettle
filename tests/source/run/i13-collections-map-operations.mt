// profiles: debug release
import alloc.hash_map
import alloc.hash_map.Entry
import alloc.vec
import alloc.vec.List
import core.clone.Clone
import core.default.Default
import core.iter.{ExtendItems, FromItems, OwnedIterable}

fn sum_values(map: read hash_map.Map<i32, i32>): i32 {
    var total = 0
    for value in map.values() { total += *value }
    total
}

fn default_value<T: Default>(): T { T.(Default).default() }

fn main(): i32 {
    // Construction, capacity and reservations.
    var empty = hash_map.new<i32, i32>()
    if !empty.is_empty() || empty.len() != 0usize { return 1 }
    if empty.get(1).is_present() || empty.contains_key(1) { return 2 }
    var defaulted: hash_map.Map<i32, i32> = default_value<hash_map.Map<i32, i32>>()
    if !defaulted.is_empty() { return 3 }
    var map = hash_map.new<i32, i32>()
    map.reserve(8usize)
    if map.capacity() < 8usize { return 4 }
    map.reserve_exact(2usize)
    match capture map.try_reserve(4usize) { success(_) => {}, failure(_) => { return 5 } }
    match capture map.try_reserve(0xffffffffffffffffusize) { success(_) => { return 6 }, failure(_) => {} }
    map.shrink_to(0usize)
    map.shrink_to_fit()

    // Insert returns the previous value; get and friends borrow entries.
    if map.insert(1, 10).is_present() { return 10 }
    if map.insert(2, 20).is_present() { return 11 }
    match map.insert(1, 11) {
        present(old) => { if old != 10 { return 12 } },
        none => { return 13 }
    }
    if map.len() != 2usize || map.is_empty() { return 14 }
    if !map.contains_key(2) || map.contains_key(3) { return 15 }
    match map.get(1) {
        present(value) => { if *value != 11 { return 16 } },
        none => { return 17 }
    }
    match map.get_key_value(2) {
        present(entry) => { if *entry.0 != 2 || *entry.1 != 20 { return 18 } },
        none => { return 19 }
    }
    match take map.get_mut(2) {
        present(value) => { *value += 1 },
        none => { return 20 }
    }
    if *map.get(2).unwrap() != 21 { return 21 }
    match capture map.try_insert(3, 30) {
        success(old) => { if old.is_present() { return 22 } },
        failure(_) => { return 23 }
    }
    match take map.get_disjoint_mut(1, 3) {
        present(pair) => {
            let (first, second) = pair
            *first += 1
            *second += 1
        },
        none => { return 24 }
    }
    if *map.get(1).unwrap() != 12 || *map.get(3).unwrap() != 31 { return 25 }

    // Entry API: occupied and vacant paths, plus the default helpers.
    match map.entry(4) {
        Entry.Vacant(_) => {},
        Entry.Occupied(_) => { return 30 }
    }
    let inserted = map.entry(4).or_insert(40)
    *inserted += 1
    if *map.get(4).unwrap() != 41 { return 31 }
    let kept = map.entry(4).or_insert(0)
    if *kept != 41 { return 32 }
    let lazy = map.entry(5).or_insert_with(take fn(): i32 { 50 })
    if *lazy != 50 { return 33 }
    let keyed = map.entry(6).or_insert_with_key(take fn(key: read i32): i32 { key * 10 })
    if *keyed != 60 { return 34 }
    map.entry(6).and_modify(take fn(value: mut i32): Unit { value += 1 }).or_insert(0)
    if *map.get(6).unwrap() != 61 { return 35 }
    let defaults = map.entry(7).or_default()
    if *defaults != 0 { return 36 }
    match take map.entry(7) {
        Entry.Occupied(occupied) => {
            var entry_view = take occupied
            if *entry_view.key() != 7 { return 37 }
            let old = entry_view.insert(70)
            if old != 0 { return 38 }
        },
        Entry.Vacant(_) => { return 39 }
    }
    match take map.entry(8) {
        Entry.Vacant(vacant) => {
            var vacant_view = take vacant
            let _ = vacant_view.insert(80)
        },
        Entry.Occupied(_) => { return 40 }
    }
    if *map.get(8).unwrap() != 80 || *map.get(7).unwrap() != 70 { return 41 }
    match take map.entry(8) {
        Entry.Occupied(occupied) => {
            let removed = occupied.remove()
            if removed != 80 { return 42 }
        },
        Entry.Vacant(_) => { return 43 }
    }
    if map.contains_key(8) { return 44 }

    // Removal returns the mapped value or the owned pair.
    match map.remove(5) {
        present(value) => { if value != 50 { return 50 } },
        none => { return 51 }
    }
    match map.remove_entry(6) {
        present(entry) => { if entry.0 != 6 || entry.1 != 61 { return 52 } },
        none => { return 53 }
    }
    if map.remove(99).is_present() { return 54 }

    // Iteration: keys, values, mutable values and extraction.
    var keys_seen = 0
    var key_total = 0
    for key in map.keys() {
        keys_seen += 1
        key_total += *key
    }
    if keys_seen != 5 || key_total != 17 { return 60 }
    for value in map.values_mut() { *value += 1 }
    if sum_values(read map) != 180 { return 61 }
    var seen_pairs = 0
    for pair in map.iter() { seen_pairs += 1 }
    if seen_pairs != 5 { return 62 }
    map.retain(fn(key: read i32, value: mut i32): bool { key != 4 })
    if map.contains_key(4) || map.len() != 4usize { return 63 }
    var extracted = 0
    for pair in map.extract_if(fn(key: read i32, value: mut i32): bool { value > 30 }) {
        extracted += pair.0
    }
    if extracted != 10 || map.len() != 2usize { return 64 }

    // Drain yields every entry and leaves the map empty.
    var drained = 0
    for pair in map.drain() { drained += pair.1 }
    if drained == 0 || !map.is_empty() { return 65 }
    map.insert(9, 90)
    match map.get(9) {
        present(value) => { if *value != 90 { return 66 } },
        none => { return 67 }
    }
    map.clear()
    if !map.is_empty() { return 68 }

    // Owned iteration, Clone, equality and collection conversions.
    var source = hash_map.new<i32, i32>()
    source.insert(1, 100)
    source.insert(2, 200)
    let duplicate = source.clone()
    if duplicate != source || duplicate.len() != 2usize { return 70 }
    var keyed_pairs = vec.new<(i32, i32)>()
    keyed_pairs.push((3, 300))
    keyed_pairs.push((4, 400))
    let built = hash_map.Map<i32, i32>.(FromItems<(i32, i32)>).from_iter(keyed_pairs)
    if built.len() != 2usize || *built.get(4).unwrap() != 400 { return 71 }
    var more = vec.new<(i32, i32)>()
    more.push((5, 500))
    source.extend(more)
    if source.len() != 3usize || *source.get(5).unwrap() != 500 { return 72 }
    var owned_total = 0
    for pair in source.into_iter() { owned_total += pair.1 }
    if owned_total != 800 { return 73 }
    0
}
