// profiles: debug release
import alloc.btree
import alloc.btree.Entry
import alloc.vec
import core.clone.Clone
import core.cmp.{Eq, Ordering}
import core.convert.From
import core.default.Default
import core.fmt.Debug
import core.hash.hash_one
import core.iter.Bound
import core.iter.{BidirectionalIterator, ExtendItems, FromItems, OwnedIterable}

fn require_debug<T: Debug>(read value: T): bool { true }
fn require_eq<T: Eq>(read value: T): bool { true }

type MapDrop {
    drops: ptr<mut usize>
    drop { unsafe { *self.drops += 1usize } }
}

// Counts the keys and returns -1 unless they are strictly ascending.
fn ordered_keys(read map: btree.SortedMap<i32, i32>): i32 {
    var code = 0
    var previous = -2147483647
    for key in map.keys() {
        if *key <= previous { return -1 }
        previous = *key
        code += 1
    }
    code
}

fn sum_values(read map: btree.SortedMap<i32, i32>): i32 {
    var total = 0
    for value in map.values() { total += *value }
    total
}

fn main(): i32 {
    // Construction and insertion; insert reports the replaced value.
    var empty = btree.new<i32, i32>()
    if !empty.is_empty() || empty.len() != 0usize || empty.contains_key(1) { return 1 }
    if empty.first_key().is_present() || empty.last_key().is_present() { return 2 }
    var map = btree.new<i32, i32>()
    if map.insert(5, 50).is_present() { return 3 }
    if map.insert(1, 10).is_present() || map.insert(9, 90).is_present() { return 4 }
    if !require_debug(read map) { return 96 }
    match map.insert(5, 55) {
        present(old) => { if old != 50 { return 5 } },
        none => { return 6 }
    }
    match capture map.try_insert(3, 30) {
        success(old) => { if old.is_present() { return 7 } },
        failure(_) => { return 8 }
    }
    if map.len() != 4usize || map.is_empty() { return 9 }
    if ordered_keys(read map) != 4 { return 10 }

    // Lookups, endpoints and borrowed entries.
    if !map.contains_key(3) || map.contains_key(4) { return 11 }
    match map.get(9) {
        present(value) => { if *value != 90 { return 12 } },
        none => { return 13 }
    }
    match map.get_key_value(1) {
        present(entry) => { if *entry.0 != 1 || *entry.1 != 10 { return 14 } },
        none => { return 15 }
    }
    match take map.get_mut(3) {
        present(value) => { *value += 1 },
        none => { return 16 }
    }
    if *map.get(3).or_panic() != 31 { return 17 }
    if map[3] != 31 || map[9] != 90 { return 23 }
    if *map.first_key().or_panic() != 1 || *map.last_key().or_panic() != 9 { return 18 }
    let (first_key, first_value) = map.first_key_value().or_panic()
    if *first_key != 1 || *first_value != 10 { return 19 }
    let (last_key, last_value) = map.last_key_value().or_panic()
    if *last_key != 9 || *last_value != 90 { return 20 }
    match take map.last_entry() {
        present(entry) => { if *entry.key() != 9 { return 21 } },
        none => { return 22 }
    }

    // Ordered removal from both ends and by key.
    match take map.first_entry() {
        present(entry) => {
            var view = take entry
            if *view.key() != 1 || *view.get() != 10 { return 21 }
            let removed = view.remove()
            if removed != 10 { return 22 }
        },
        none => { return 23 }
    }
    match map.pop_last() {
        present(pair) => { if pair.0 != 9 || pair.1 != 90 { return 24 } },
        none => { return 25 }
    }
    match map.pop_first() {
        present(pair) => { if pair.0 != 3 || pair.1 != 31 { return 26 } },
        none => { return 27 }
    }
    if map.len() != 1usize { return 28 }
    match map.pop_first() {
        present(pair) => { if pair.0 != 5 || pair.1 != 55 { return 29 } },
        none => { return 30 }
    }
    if map.pop_first().is_present() || !map.is_empty() { return 31 }
    map.insert(2, 20)
    map.insert(4, 40)
    if map.remove(2).is_present() == false { return 30 }
    if map.remove(2).is_present() { return 31 }
    match map.remove_entry(4) {
        present(pair) => { if pair.0 != 4 || pair.1 != 40 { return 32 } },
        none => { return 33 }
    }
    if !map.is_empty() { return 34 }

    // Entry API on an ordered map.
    var counts = btree.new<i32, i32>()
    if !require_debug(read counts.entry(1)) { return 90 }
    let fresh = counts.entry(1).or_insert(7)
    *fresh += 1
    if *counts.get(1).or_panic() != 8 { return 40 }
    let seeded = counts.entry(2).or_insert_with(take fn(): i32 { 20 })
    if *seeded != 20 { return 41 }
    let keyed = counts.entry(3).or_insert_with_key(take fn(read key: i32): i32 { key * 100 })
    if *keyed != 300 { return 42 }
    counts.entry(3).and_modify(take fn(mut value: i32): Unit { value += 1 }).or_insert(0)
    if *counts.get(3).or_panic() != 301 { return 43 }
    let defaulted = counts.entry(4).or_default()
    if *defaulted != 0 { return 44 }
    {
        var inserted = counts.entry(6).insert_entry(600)
        if *inserted.key() != 6 || *inserted.get() != 600 { return 45 }
        if inserted.remove() != 600 { return 46 }
    }
    match take counts.entry(4) {
        Entry.Occupied(occupied) => {
            var view = take occupied
            let old = view.insert(44)
            if old != 0 { return 45 }
        },
        Entry.Vacant(_) => { return 46 }
    }
    match take counts.entry(5) {
        Entry.Vacant(vacant) => {
            var slot = take vacant
            let _ = slot.insert(55)
        },
        Entry.Occupied(_) => { return 47 }
    }
    match take counts.entry(5) {
        Entry.Occupied(occupied) => {
            var view = take occupied
            let slot = view.into_mut()
            *slot += 1
        },
        Entry.Vacant(_) => { return 48 }
    }
    if *counts.get(5).or_panic() != 56 { return 49 }
    match take counts.entry(2) {
        Entry.Occupied(occupied) => {
            var view = take occupied
            if *view.get() != 20 { return 50 }
        },
        Entry.Vacant(_) => { return 51 }
    }

    // Range bounds select endpoint inclusion and visit keys in ascending order.
    var range_total = 0
    var range_count = 0
    for entry in counts.range(core.iter.range(2, 5)) {
        range_total += entry.value
        range_count += 1
    }
    if range_count != 3 || range_total != 20 + 301 + 44 { return 52 }
    var inclusive_total = 0
    var inclusive_count = 0
    for entry in counts.range((Bound.Included(2), Bound.Included(5))) {
        inclusive_total += entry.value
        inclusive_count += 1
    }
    if inclusive_count != 4 || inclusive_total != 20 + 301 + 44 + 56 { return 150 }
    var unbounded_count = 0
    for entry in counts.range((Bound.Unbounded, Bound.Excluded(2))) { unbounded_count += 1 }
    if unbounded_count != 1 { return 151 }
    var all_count = 0
    for entry in counts.range((Bound.Unbounded, Bound.Unbounded)) { all_count += 1 }
    if all_count != counts.len() { return 153 }
    var singleton_count = 0
    for entry in counts.range((Bound.Included(3), Bound.Included(3))) { singleton_count += 1 }
    if singleton_count != 1 { return 154 }
    match take std.panic.catch_panic(fn(): Unit {
        let _ = counts.range((Bound.Excluded(3), Bound.Excluded(3)))
    }) {
        std.panic.CatchResult.Panicked(_) => {},
        _ => { return 152 }
    }
    {
        var writes = counts.range_mut((Bound.Included(1), Bound.Excluded(3)))
        match take writes.next() {
            present(value) => { *value = 80 },
            none => { return 53 }
        }
        match take writes.next_back() {
            present(_) => {},
            none => { return 53 }
        }
        if writes.next().is_present() { return 53 }
    }
    if *counts.get(1).or_panic() != 80 { return 54 }
    var empty_range = 0
    for entry in counts.range(core.iter.range(3, 3)) { empty_range += 1 }
    if empty_range != 0 { return 55 }

    // Filtering, splitting and iteration.
    var extracted = 0
    for pair in counts.extract_if(core.iter.range_full(), fn(read key: i32, mut value: i32): bool { value > 100 }) {
        extracted += pair.0
    }
    var drops = 0usize
    {
        var dropping = btree.new<i32, MapDrop>()
        dropping.insert(1, MapDrop(core.ptr.from_mut(drops)))
        dropping.insert(2, MapDrop(core.ptr.from_mut(drops)))
        dropping.insert(3, MapDrop(core.ptr.from_mut(drops)))
    }
    if drops != 3usize { return 91 }
    {
        var dropping = btree.new<i32, MapDrop>()
        dropping.insert(1, MapDrop(core.ptr.from_mut(drops)))
        dropping.insert(2, MapDrop(core.ptr.from_mut(drops)))
        dropping.insert(3, MapDrop(core.ptr.from_mut(drops)))
        var items = dropping.into_iter()
        if items.next().is_none() { return 92 }
    }
    if drops != 6usize { return 93 }
    var same_map = btree.new<i32, i32>()
    same_map.insert(2, 20)
    same_map.insert(1, 10)
    var reordered_map = btree.new<i32, i32>()
    reordered_map.insert(1, 10)
    reordered_map.insert(2, 20)
    if !require_eq(read same_map) || !(same_map == reordered_map) ||
        hash_one(read same_map) != hash_one(read reordered_map) {
        return 94
    }
    if extracted != 3 || counts.len() != 4usize { return 56 }
    counts.retain(fn(read key: i32, mut value: i32): bool { key != 4 })
    if counts.contains_key(4) || counts.len() != 3usize { return 57 }
    var upper = counts.split_off(2)
    if counts.len() != 1usize || upper.len() != 2usize || !upper.contains_key(5) { return 58 }
    for value in upper.values_mut() { *value += 1 }
    {
        var values = upper.values_mut()
        let remaining = values.size_hint().0
        if !values.next_back().is_present() ||
            values.size_hint().0 != remaining - 1usize ||
            !values.next().is_present() ||
            values.size_hint().0 != remaining - 2usize {
            return 155
        }
    }
    if sum_values(read upper) != 21 + 57 { return 59 }
    var walked = 0
    for entry in upper.iter() { walked += 1 }
    if walked != 2 { return 60 }
    for entry in upper.iter_mut() { *entry.1 += 1 }
    if sum_values(read upper) != 22 + 58 { return 61 }

    // Clone, comparisons, Default, Debug-free conversions and owned iteration.
    var source = btree.new<i32, i32>()
    source.insert(1, 1)
    source.insert(2, 2)
    let duplicate = source.clone()
    if duplicate != source || duplicate.len() != 2usize { return 70 }
    var larger = btree.new<i32, i32>()
    larger.insert(1, 1)
    larger.insert(3, 0)
    if !(source < larger) || source.cmp(larger) != Ordering.Less { return 71 }
    var keyed_pairs = vec.new<(i32, i32)>()
    keyed_pairs.push((7, 70))
    keyed_pairs.push((6, 60))
    let built = btree.SortedMap<i32, i32>.(FromItems<(i32, i32)>).from_iter(keyed_pairs)
    if *built.first_key().or_panic() != 6 || built.len() != 2usize { return 72 }
    var more = vec.new<(i32, i32)>()
    more.push((8, 80))
    var grown = built
    grown.extend(more)
    if grown.len() != 3usize { return 73 }
    var owned_total = 0
    for pair in grown.into_iter() { owned_total += pair.value }
    if owned_total != 210 { return 74 }

    var appended = btree.new<i32, i32>()
    appended.insert(1, 10)
    appended.insert(2, 20)
    var append_source = btree.new<i32, i32>()
    append_source.insert(2, 200)
    append_source.insert(3, 30)
    appended.append(mut append_source)
    if appended.len() != 3usize || !append_source.is_empty() ||
        *appended.get(2).or_panic() != 200 {
        return 75
    }
    appended.clear()
    if !appended.is_empty() { return 76 }

    let array_map = btree.SortedMap<i32, i32>.(From<[(i32, i32); 3]>).from([(3, 30), (1, 10), (3, 31)])
    if array_map.len() != 2usize || *array_map.get(3).or_panic() != 31 { return 77 }
    let array_set = btree.SortedSet<i32>.(From<[i32; 3]>).from([3, 1, 3])
    if array_set.len() != 2usize || *array_set.first().or_panic() != 1 { return 78 }

    var keys_map = btree.new<i32, i32>()
    keys_map.insert(2, 20)
    keys_map.insert(1, 10)
    var keys_sum = 0
    for key in keys_map.into_keys() { keys_sum += key }
    if keys_sum != 3 { return 79 }
    var values_map = btree.new<i32, i32>()
    values_map.insert(2, 20)
    values_map.insert(1, 10)
    var values_sum = 0
    for value in values_map.into_values() { values_sum += value }
    if values_sum != 30 { return 80 }
    0
}
