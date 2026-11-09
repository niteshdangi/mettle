import alloc.hash_map.Map
import core.hash.{Hash, Hasher}
import package.core.cmp.PartialEq

// Every key hashes to the same value, so all lookups walk one probe chain.
copy type Same { id: i32 }
extend Same implements Hash { fn hash<H: Hasher>(mut state: H): Unit { state.write_u64(7u64) } }
extend Same implements PartialEq { fn eq(read other: Same): bool { self.id == other.id } }

fn main(): i32 {
    var m = alloc.hash_map.new<Same, i32>()
    var i = 0
    while i < 300 { let r = m.insert(Same(i + 0), i * 2); i += 1 }
    if m.len() != 300usize { return 1 }
    i = 0
    while i < 300 {
        match m.get(Same(i + 0)) { present(v) => { if *v != i * 2 { return 2 } }, none => { return 3 } }
        i += 1
    }
    i = 0
    while i < 300 { if i % 3 == 0 { match m.remove(Same(i + 0)) { present(_) => {}, none => { return 4 } } }; i += 1 }
    i = 0
    while i < 300 { if m.contains_key(Same(i + 0)) != (i % 3 != 0) { return 5 }; i += 1 }
    if m.len() != 200usize { return 6 }
    match m.remove_entry(Same(1)) {
        present(entry) => {
            if entry.0.id != 1 || entry.1 != 2 { return 9 }
        },
        none => { return 10 }
    }
    if m.contains_key(Same(1)) { return 11 }
    let v = m.or_insert(Same(1000), 5)
    var set = alloc.hash_map.set_new<i32>()
    if !set.insert(1) || set.insert(1) || !set.contains(1) || set.contains(2) { return 7 }
    if !set.remove(1) || set.remove(1) || set.len() != 0usize { return 8 }
    0
}
