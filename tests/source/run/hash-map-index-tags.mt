import alloc.hash_map
import core.hash.{BuildHasher, Hash, Hasher}

copy type Key { id: i32; tag: i32 }
extend Key implements PartialEq {
    fn eq(read other: Key): bool { self.id == other.id }
}
extend Key implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        let tag = (self.id as u64) & 15u64
        state.write_u64(((if tag == 15u64 { 127u64 } else { tag }) << 57u64) | 31u64)
    }
}

type DirectHasher { value: u64; shift: u64 }
extend DirectHasher implements Hasher {
    mut fn write(read bytes: [u8]): Unit {
        var i = 0usize
        while i < bytes.len() {
            self.value = self.value | ((bytes[i] as u64) << self.shift)
            self.shift += 8u64
            i += 1usize
        }
    }
    fn finish(): u64 { self.value }
}
copy type DirectBuilder {}
extend DirectBuilder implements BuildHasher {
    type Hasher = DirectHasher
    fn build_hasher(): DirectHasher { DirectHasher(0u64, 0u64) }
}

fn main(): i32 {
    var map = hash_map.with_hasher<Key, i32, DirectBuilder>(DirectBuilder())
    var i = 0
    while i < 24 {
        if map.insert(Key(i, i), i * 10).is_present() { return 1 }
        i += 1
    }
    if map.insert(Key(16, 99), 161).or_panic() != 160 { return 2 }
    match map.get_key_value(Key(16, 99)) {
        present(entry) => { if entry.0.tag != 16 || *entry.1 != 161 { return 15 } },
        none => { return 16 }
    }
    match take map.get_mut(Key(15, 99)) {
        present(value) => { *value = 151 },
        none => { return 3 }
    }
    *map.or_insert(Key(31, 31), 310) = 311
    map.reserve(80usize)
    map.shrink_to_fit()
    if map.remove(Key(0, 99)).or_panic() != 0 { return 4 }
    if *map.get(Key(31, 99)).or_panic() != 311 { return 5 }
    i = 1
    while i < 24 {
        let expected = if i == 15 { 151 } else if i == 16 { 161 } else { i * 10 }
        if *map.get(Key(i, 99)).or_panic() != expected { return 6 }
        i += 1
    }
    if map.get(Key(32, 99)).is_present() { return 7 }
    map.retain(fn(read key: Key, mut value: i32): bool { key.id % 3 != 0 })
    i = 0
    while i < 24 {
        if map.contains_key(Key(i, 99)) != (i % 3 != 0) { return 8 }
        i += 1
    }
    var visited = 0usize
    for entry in map.iter() {
        if !map.contains_key(entry.key) { return 9 }
        visited += 1usize
    }
    if map.len() != 17usize || visited != 17usize { return 9 }
    for pair in map.drain() {}
    if !map.is_empty() || map.get(Key(31, 99)).is_present() { return 10 }
    map.insert(Key(15, 15), 50)
    if *map.get(Key(15, 99)).or_panic() != 50 { return 11 }

    var set = hash_map.set_with_hasher<Key, DirectBuilder>(DirectBuilder())
    if !set.insert(Key(15, 10)) || !set.insert(Key(31, 30)) { return 12 }
    let replaced = set.replace(Key(15, 20)).or_panic()
    if replaced.tag != 10 || set.get(Key(15, 99)).or_panic().tag != 20 { return 13 }
    if !set.remove(Key(15, 99)) || !set.contains(Key(31, 99)) { return 14 }
    var small = hash_map.with_hasher<Key, i32, DirectBuilder>(DirectBuilder())
    var round = 0
    while round < 8 {
        i = 0
        while i < 7 {
            let id = if i == 6 { 15 } else { i }
            if small.insert(Key(id, id), round * 10 + i).is_present() { return 17 }
            i += 1
        }
        i = 0
        while i < 7 {
            let id = if i == 6 { 15 } else { i }
            if *small.get(Key(id, 99)).or_panic() != round * 10 + i { return 18 }
            i += 1
        }
        if small.get(Key(7, 99)).is_present() { return 19 }
        let full_capacity = small.capacity()
        let expected = round * 10
        if small.remove(Key(0, 99)).or_panic() != expected ||
            small.insert(Key(7, 7), expected + 1).is_present() ||
            small.capacity() != full_capacity ||
            *small.get(Key(7, 99)).or_panic() != expected + 1 { return 24 }
        if small.remove(Key(7, 99)).or_panic() != expected + 1 ||
            small.insert(Key(0, 0), expected + 0).is_present() { return 25 }
        i = 0
        while i < 7 {
            let id = if i == 6 { 15 } else { i }
            if small.remove(Key(id, 99)).or_panic() != round * 10 + i { return 20 }
            i += 1
        }
        if !small.is_empty() || small.get(Key(15, 99)).is_present() { return 21 }
        if round % 2 == 0 { small.reserve(7usize) }
        round += 1
    }
    var units = hash_map.new<Unit, Unit>()
    units.reserve(32usize)
    if units.insert((), ()).is_present() || !units.get(()).is_present() { return 22 }
    units.shrink_to_fit()
    if !units.remove(()).is_present() || !units.is_empty() { return 23 }
    units.clear()
    units.shrink_to_fit()
    0
}
