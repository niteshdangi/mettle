// expect-exit: 0
import alloc.btree
import alloc.hash_map
import core.cmp.{ Eq, Ord, Ordering, PartialEq, PartialOrd }
import core.hash.{ Hash, Hasher }

copy type TaggedKey { id: i32; tag: i32 }

extend TaggedKey implements PartialEq {
    fn eq(other: read TaggedKey): bool { self.id == other.id }
}
extend TaggedKey implements Eq {}
extend TaggedKey implements PartialOrd {
    fn partial_cmp(other: read TaggedKey): Ordering? { present(self.cmp(other)) }
}
extend TaggedKey implements Ord {
    fn cmp(other: read TaggedKey): Ordering { self.id.cmp(other.id) }
}
extend TaggedKey implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { state.write_u32(self.id as u32) }
}

// The single-threaded counter outlives every key, including query keys.
type TrackedKey {
    key: TaggedKey
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
extend TrackedKey implements PartialEq {
    fn eq(other: read TrackedKey): bool { self.key == other.key }
}
extend TrackedKey implements Eq {}
extend TrackedKey implements PartialOrd {
    fn partial_cmp(other: read TrackedKey): Ordering? { present(self.cmp(other)) }
}
extend TrackedKey implements Ord {
    fn cmp(other: read TrackedKey): Ordering { self.key.cmp(other.key) }
}
extend TrackedKey implements Hash {
    fn hash<H: Hasher>(state: mut H): Unit { self.key.hash(mut state) }
}

fn noncopy_keys(): Unit {
    var drops = 0
    let counter = core.ptr.from_mut(drops)
    let query = TrackedKey(TaggedKey(1, 99), counter)
    {
        var values = hash_map.set_new<TrackedKey>()
        assert(values.insert(TrackedKey(TaggedKey(1, 10), counter)), "insert owner")
        assert(!values.insert(TrackedKey(TaggedKey(1, 11), counter)), "duplicate drops")
        assert(drops == 1, "duplicate dropped exactly once")
        match values.get(read query) {
            present(found) => { assert((*found).key.tag == 10, "borrow stored key") },
            none => { panic("missing stored key") }
        }
        match take values.replace(TrackedKey(TaggedKey(1, 20), counter)) {
            present(old) => {
                assert(old.key.tag == 10 && drops == 1, "replace transfers old owner")
                core.mem.drop(take old)
            },
            none => { panic("missing replaced key") }
        }
        assert(values.replace(TrackedKey(TaggedKey(2, 30), counter)).is_none(),
            "replace missing inserts")
        match take values.`take`(read query) {
            present(old) => {
                assert(old.key.tag == 20 && drops == 2, "take transfers replacement")
                core.mem.drop(take old)
            },
            none => { panic("missing taken key") }
        }
        assert(query.key.tag == 99 && drops == 3, "queries remain owned by caller")
    }
    assert(drops == 4, "hash set drops remaining owner once")
    {
        var values = btree.set_new<TrackedKey>()
        assert(values.insert(TrackedKey(TaggedKey(1, 10), counter)), "insert owner")
        assert(!values.insert(TrackedKey(TaggedKey(1, 11), counter)), "duplicate drops")
        assert(drops == 5, "duplicate dropped exactly once")
        match values.get(read query) {
            present(found) => { assert((*found).key.tag == 10, "borrow stored key") },
            none => { panic("missing stored key") }
        }
        match take values.replace(TrackedKey(TaggedKey(1, 20), counter)) {
            present(old) => {
                assert(old.key.tag == 10 && drops == 5, "replace transfers old owner")
                core.mem.drop(take old)
            },
            none => { panic("missing replaced key") }
        }
        assert(values.replace(TrackedKey(TaggedKey(2, 30), counter)).is_none(),
            "replace missing inserts")
        match take values.`take`(read query) {
            present(old) => {
                assert(old.key.tag == 20 && drops == 6, "take transfers replacement")
                core.mem.drop(take old)
            },
            none => { panic("missing taken key") }
        }
        assert(query.key.tag == 99 && drops == 7, "queries remain owned by caller")
    }
    assert(drops == 8, "sorted set drops remaining owner once")
    core.mem.drop(take query)
    assert(drops == 9, "query drops exactly once")
}

fn main(): i32 {
    var hashed = hash_map.set_new<TaggedKey>()
    if !hashed.insert(TaggedKey(1, 10)) { return 1 }
    if hashed.insert(TaggedKey(1, 11)) { return 2 }
    match hashed.get(TaggedKey(1, 99)) {
        present(found) => { if (*found).tag != 10 { return 3 } },
        none => { return 4 }
    }
    match hashed.replace(TaggedKey(1, 20)) {
        present(old) => { if old.tag != 10 { return 5 } },
        none => { return 6 }
    }
    match hashed.get(TaggedKey(1, 99)) {
        present(found) => { if (*found).tag != 20 { return 7 } },
        none => { return 8 }
    }
    match hashed.replace(TaggedKey(2, 30)) {
        present(_) => { return 9 },
        none => {}
    }
    match hashed.get(TaggedKey(2, 99)) {
        present(found) => { if (*found).tag != 30 { return 10 } },
        none => { return 11 }
    }
    match hashed.get(TaggedKey(3, 99)) {
        present(_) => { return 12 },
        none => {}
    }
    match hashed.`take`(TaggedKey(1, 99)) {
        present(old) => { if old.tag != 20 { return 13 } },
        none => { return 14 }
    }
    if hashed.len() != 1usize { return 15 }

    var ordered = btree.set_new<TaggedKey>()
    if !ordered.insert(TaggedKey(1, 10)) { return 16 }
    if ordered.insert(TaggedKey(1, 11)) { return 17 }
    match ordered.get(TaggedKey(1, 99)) {
        present(found) => { if (*found).tag != 10 { return 18 } },
        none => { return 19 }
    }
    match ordered.replace(TaggedKey(1, 20)) {
        present(old) => { if old.tag != 10 { return 20 } },
        none => { return 21 }
    }
    match ordered.get(TaggedKey(1, 99)) {
        present(found) => { if (*found).tag != 20 { return 22 } },
        none => { return 23 }
    }
    match ordered.replace(TaggedKey(2, 30)) {
        present(_) => { return 24 },
        none => {}
    }
    match ordered.get(TaggedKey(2, 99)) {
        present(found) => { if (*found).tag != 30 { return 25 } },
        none => { return 26 }
    }
    match ordered.get(TaggedKey(3, 99)) {
        present(_) => { return 27 },
        none => {}
    }
    match ordered.`take`(TaggedKey(1, 99)) {
        present(old) => { if old.tag != 20 { return 28 } },
        none => { return 29 }
    }
    if ordered.len() != 1usize { return 30 }
    noncopy_keys()
    0
}
