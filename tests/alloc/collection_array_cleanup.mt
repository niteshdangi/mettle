import core.cmp.{PartialEq, Eq, PartialOrd, Ord, Ordering}
import core.convert.From
import core.hash.{Hash, Hasher}
import std.panic.{catch_panic, CatchResult}

type Key {
    value: i32
    index: usize
    drops: ptr<mut i32>
    fail: bool
    drop { unsafe { *self.drops.add(self.index) += 1 } }
}
extend Key implements PartialEq {
    fn eq(read other: Key): bool { self.value == other.value }
}
extend Key implements Eq {}
extend Key implements PartialOrd {
    fn partial_cmp(read other: Key): Ordering? { present(self.cmp(other)) }
}
extend Key implements Ord {
    fn cmp(read other: Key): Ordering {
        if self.fail && (self.value == 3 || other.value == 3) {
            core.panic.panic("comparison")
        }
        self.value.cmp(other.value)
    }
}
extend Key implements Hash {
    fn hash<H: Hasher>(mut state: H): Unit {
        if self.fail && self.value == 3 { core.panic.panic("hash") }
        state.write_i32(self.value)
    }
}

fn check<F: take fn(take [Key; 4]): bool>(fail: bool, take build: F): bool {
    var drops = [0i32; 4]
    let counter = core.ptr.from_mut(drops).cast<i32>()
    let items = [
        Key(2, 0usize, counter, fail),
        Key(1, 1usize, counter, fail),
        Key(2, 2usize, counter, fail),
        Key(3, 3usize, counter, fail)
    ]
    let result = catch_panic(take fn(): bool { build(take items) })
    if drops[0usize] != 1 || drops[1usize] != 1 ||
        drops[2usize] != 1 || drops[3usize] != 1 { return false }
    match take result {
        CatchResult.Returned(valid) => !fail && valid,
        CatchResult.Panicked(_) => fail
    }
}

fn checks(fail: bool): i32 {
    if !check(fail, take fn(take keys: [Key; 4]): bool {
        let [a, b, c, d] = take keys
        let map = alloc.hash_map.Map<Key, i32>.(From<[(Key, i32); 4]>).from(
            [(a, 10), (b, 20), (c, 30), (d, 40)])
        var sum = 0
        for value in map.values() { sum += *value }
        map.len() == 3usize && sum == 90
    }) { return 1 }
    if !check(fail, take fn(take keys: [Key; 4]): bool {
        let [a, b, c, d] = take keys
        let map = alloc.btree.SortedMap<Key, i32>.(From<[(Key, i32); 4]>).from(
            [(a, 10), (b, 20), (c, 30), (d, 40)])
        var sum = 0
        for value in map.values() { sum += *value }
        map.len() == 3usize && sum == 90
    }) { return 2 }
    if !check(fail, take fn(take keys: [Key; 4]): bool {
        let set = alloc.hash_map.Set<Key>.(From<[Key; 4]>).from(take keys)
        set.len() == 3usize
    }) { return 3 }
    if !check(fail, take fn(take keys: [Key; 4]): bool {
        let set = alloc.btree.SortedSet<Key>.(From<[Key; 4]>).from(take keys)
        set.len() == 3usize
    }) { return 4 }
    0
}

fn main(): i32 {
    let normal = checks(false)
    if normal != 0 { return normal }
    checks(true)
}
