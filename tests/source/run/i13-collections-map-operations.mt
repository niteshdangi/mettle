// profiles: debug release
import alloc.hash_map
import alloc.hash_map.Entry
import alloc.vec
import alloc.vec.List
import core.clone.Clone
import core.cmp.Eq
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.hash.{BuildHasher, SipHasher, sip13}
import core.iter.{ExtendItems, FromItems, OwnedIterable}

fn require_debug<T: Debug>(read value: T): bool { true }
fn require_eq<T: Eq>(read value: T): bool { true }

pub copy type TestBuildHasher { pub key: u64 }
extend TestBuildHasher implements BuildHasher {
    type Hasher = SipHasher
    fn build_hasher(): SipHasher { sip13(self.key, self.key ^ 0x9e3779b97f4a7c15u64) }
}

fn sum_values(read map: hash_map.Map<i32, i32>): i32 {
    var total = 0
    for value in map.values() { total += *value }
    total
}

fn default_value<T: Default>(): T { T.(Default).default() }

fn check_borrowed_iterator_defaults<region r, S: BuildHasher>(
    read map: hash_map.Map<i32, i32, alloc.alloc.Global, S> from r
): bool {
    var entries: hash_map.Iter<region r, i32, i32> =
        default_value<hash_map.Iter<region r, i32, i32>>()
    var keys: hash_map.Keys<region r, i32, i32> =
        default_value<hash_map.Keys<region r, i32, i32>>()
    var values: hash_map.Values<region r, i32, i32> =
        default_value<hash_map.Values<region r, i32, i32>>()
    var entries_mut: hash_map.IterMut<region r, i32, i32, alloc.alloc.Global, S> =
        default_value<hash_map.IterMut<region r, i32, i32, alloc.alloc.Global, S>>()
    var values_mut: hash_map.ValuesMut<region r, i32, i32, alloc.alloc.Global, S> =
        default_value<hash_map.ValuesMut<region r, i32, i32, alloc.alloc.Global, S>>()
    var entries_copy = entries.clone()
    var keys_copy = keys.clone()
    var values_copy = values.clone()
    require_debug(read entries)
    require_debug(read keys)
    require_debug(read values)
    require_debug(read entries_mut)
    require_debug(read values_mut)
    entries.size_hint() == (0usize, present(0usize)) &&
        keys.size_hint() == (0usize, present(0usize)) &&
        values.size_hint() == (0usize, present(0usize)) &&
        entries_mut.size_hint() == (0usize, present(0usize)) &&
        values_mut.size_hint() == (0usize, present(0usize)) &&
        !entries_copy.next().is_present() &&
        !keys_copy.next().is_present() &&
        !values_copy.next().is_present()
}

fn main(): i32 {
    // Construction, capacity and reservations.
    var empty = hash_map.new<i32, i32>()
    if !empty.is_empty() || empty.len() != 0usize { return 1 }
    if empty.get(1).is_present() || empty.contains_key(1) { return 2 }
    var defaulted: hash_map.Map<i32, i32> = default_value<hash_map.Map<i32, i32>>()
    if !defaulted.is_empty() { return 3 }
    var default_hash = hash_map.new<i32, i32>()
    default_hash.insert(7, 70)
    if default_hash.as_entries()[0usize].hash != core.hash.hash_one(7i32) {
        return 9
    }
    var custom = hash_map.with_hasher<i32, i32, TestBuildHasher>(TestBuildHasher(17u64))
    custom.insert(7, 70)
    if custom.hasher().key != 17u64 ||
        custom.as_entries()[0usize].hash != custom.hasher().hash_one(7i32) ||
        *custom.get(7).or_panic() != 70 {
        return 8
    }
    var capacity_custom =
        hash_map.with_capacity_and_hasher<i32, i32, TestBuildHasher>(4usize, TestBuildHasher(23u64))
    if capacity_custom.capacity() < 4usize { return 7 }
    capacity_custom.insert(3, 30)
    if *capacity_custom.get(3).or_panic() != 30 { return 6 }
    var capacity_custom_in = hash_map.with_capacity_and_hasher_in<
        i32, i32, alloc.alloc.Global, TestBuildHasher
    >(3usize, alloc.alloc.Global(), TestBuildHasher(29u64))
    if capacity_custom_in.capacity() < 3usize { return 4 }
    capacity_custom_in.insert(5, 50)
    if *capacity_custom_in.get(5).or_panic() != 50 { return 3 }
    var custom_set = hash_map.set_with_hasher<i32, TestBuildHasher>(TestBuildHasher(31u64))
    custom_set.insert(11)
    if custom_set.hasher().key != 31u64 || !custom_set.contains(11) ||
        custom_set.as_entries()[0usize].hash != custom_set.hasher().hash_one(11i32) {
        return 86
    }
    var custom_set_capacity =
        hash_map.set_with_capacity_and_hasher<i32, TestBuildHasher>(2usize, TestBuildHasher(33u64))
    if custom_set_capacity.capacity() < 2usize || custom_set_capacity.hasher().key != 33u64 {
        return 87
    }
    custom_set_capacity.insert(12)
    if !custom_set_capacity.contains(12) { return 88 }
    var custom_set_capacity_in = hash_map.set_with_capacity_and_hasher_in<
        i32, alloc.alloc.Global, TestBuildHasher
    >(2usize, alloc.alloc.Global(), TestBuildHasher(37u64))
    if custom_set_capacity_in.capacity() < 2usize { return 2 }
    custom_set_capacity_in.insert(13)
    if !custom_set_capacity_in.contains(13) { return 1 }
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
    if !require_debug(read map) { return 98 }
    match map.insert(1, 11) {
        present(old) => { if old != 10 { return 12 } },
        none => { return 13 }
    }
    if map.len() != 2usize || map.is_empty() { return 14 }
    if !check_borrowed_iterator_defaults(read map) { return 14 }
    if map[1] != 11 || map[2] != 20 { return 27 }
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
    unsafe {
        let pair = map.get_disjoint_unchecked_mut(1, 2)
        *pair.0 += 1
        *pair.1 += 2
    }
    if *map.get(1).or_panic() != 12 || *map.get(2).or_panic() != 23 { return 21 }
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
    if *map.get(1).or_panic() != 13 || *map.get(3).or_panic() != 31 { return 25 }
    unsafe {
        let pair = map.get_disjoint_unchecked_mut(1, 3)
        *pair.0 += 1
        *pair.1 += 1
    }
    if *map.get(1).or_panic() != 14 || *map.get(3).or_panic() != 32 { return 26 }

    // Entry API: occupied and vacant paths, plus the default helpers.
    if !require_debug(read map.entry(4)) { return 28 }
    match map.entry(4) {
        Entry.Vacant(_) => {},
        Entry.Occupied(_) => { return 30 }
    }
    let inserted = map.entry(4).or_insert(40)
    *inserted += 1
    if *map.get(4).or_panic() != 41 { return 31 }
    let kept = map.entry(4).or_insert(0)
    if *kept != 41 { return 32 }
    let lazy = map.entry(5).or_insert_with(take fn(): i32 { 50 })
    if *lazy != 50 { return 33 }
    let keyed = map.entry(6).or_insert_with_key(take fn(read key: i32): i32 { key * 10 })
    if *keyed != 60 { return 34 }
    map.entry(6).and_modify(take fn(mut value: i32): Unit { value += 1 }).or_insert(0)
    if *map.get(6).or_panic() != 61 { return 35 }
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
    if *map.get(8).or_panic() != 80 || *map.get(7).or_panic() != 70 { return 41 }
    {
        var inserted = map.entry(10).insert_entry(100)
        if *inserted.key() != 10 || *inserted.get() != 100 { return 45 }
    }
    {
        var replaced = map.entry(10).insert_entry(101)
        if *replaced.key() != 10 || *replaced.get() != 101 { return 46 }
    }
    let _ = map.remove(10)
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
    if sum_values(read map) != 185 { return 61 }
    var seen_pairs = 0
    for pair in map.iter() { seen_pairs += 1 }
    if seen_pairs != 5 { return 62 }
    map.retain(fn(read key: i32, mut value: i32): bool { key != 4 })
    if map.contains_key(4) || map.len() != 4usize { return 63 }
    var extracted = 0
    for pair in map.extract_if(fn(read key: i32, mut value: i32): bool { value > 30 }) {
        extracted += pair.0
    }
    if extracted != 10 || map.len() != 2usize { return 64 }

    // Drain yields every entry and leaves the map empty.
    var drained = 0
    var drain_count = 0
    for pair in map.drain() { drained += pair.1; drain_count += 1 }
    if drained != 39 || drain_count != 2 || !map.is_empty() { return 65 }
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
    if !require_eq(read duplicate) || duplicate != source || duplicate.len() != 2usize { return 70 }
    var keyed_pairs = vec.new<(i32, i32)>()
    keyed_pairs.push((3, 300))
    keyed_pairs.push((4, 400))
    let built = hash_map.Map<i32, i32>.(FromItems<(i32, i32)>).from_iter(keyed_pairs)
    if built.len() != 2usize || *built.get(4).or_panic() != 400 { return 71 }
    var more = vec.new<(i32, i32)>()
    more.push((5, 500))
    source.extend(more)
    if source.len() != 3usize || *source.get(5).or_panic() != 500 { return 72 }
    var owned_total = 0
    for pair in source.into_iter() { owned_total += pair.1 }
    if owned_total != 800 { return 73 }

    var debug_map = hash_map.new<i32, i32>()
    debug_map.insert(1, 10)
    var debug_drain = debug_map.drain()
    if !require_debug(read debug_drain) { return 85 }

    var sized = hash_map.with_capacity<i32, i32>(5usize)
    if sized.capacity() < 5usize { return 74 }
    var sized_set = hash_map.set_with_capacity<i32>(5usize)
    if sized_set.capacity() < 5usize { return 75 }

    let from_array = hash_map.Map<i32, i32>.(From<[(i32, i32); 2]>).from([(1, 10), (2, 20)])
    if from_array.len() != 2usize || *from_array.get(2).or_panic() != 20 { return 76 }
    let set_array = hash_map.Set<i32>.(From<[i32; 3]>).from([2, 2, 3])
    if set_array.len() != 2usize || !set_array.contains(3) { return 77 }

    var keys_source = hash_map.new<i32, i32>()
    keys_source.insert(1, 10)
    keys_source.insert(2, 20)
    var key_sum = 0
    for key in keys_source.into_keys() { key_sum += key }
    if key_sum != 3 { return 78 }
    var values_source = hash_map.new<i32, i32>()
    values_source.insert(1, 10)
    values_source.insert(2, 20)
    var value_sum = 0
    for value in values_source.into_values() { value_sum += value }
    if value_sum != 30 { return 79 }
    0
}
