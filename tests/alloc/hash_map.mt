import alloc.hash_map.Map
fn main(): i32 {
    var m = alloc.hash_map.new<i32, i64>()
    var i = 0
    while i < 1000 { let r = m.insert(i + 0, (i as i64) * 3i64); i += 1 }
    if m.len() != 1000usize { return 1 }
    let old = m.insert(7, 1i64)
    match old { present(x) => { if x != 21i64 { return 2 } }, none => { return 3 } }
    i = 0
    while i < 1000 {
        match m.get(i + 0) { present(v) => { if i != 7 && *v != (i as i64) * 3i64 { return 4 } }, none => { return 5 } }
        i += 1
    }
    i = 0
    while i < 1000 { if i % 2 == 0 { match m.remove(i + 0) { present(_) => {}, none => { return 6 } } }; i += 1 }
    if m.len() != 500usize { return 7 }
    i = 0
    while i < 1000 { if m.contains_key(i + 0) != (i % 2 == 1) { return 8 }; i += 1 }
    if m.capacity() < m.len() { return 9 }
    m.reserve_exact(100usize)
    if m.capacity() < m.len() + 100usize { return 10 }
    { let r = m.or_insert(5000, 9i64) }
    match m.remove_entry(5000 + 0) {
        present(entry) => {
            if entry.0 != 5000 || entry.1 != 9i64 { return 11 }
        },
        none => { return 12 }
    }
    m.shrink_to_fit()
    if m.capacity() < m.len() { return 13 }
    var set = alloc.hash_map.set_new<i32>()
    set.reserve_exact(20usize)
    if set.capacity() < 20usize { return 14 }
    if !set.insert(5) { return 15 }
    match set.get(5) {
        present(value) => { if *value != 5 { return 16 } },
        none => { return 17 }
    }
    match set.`take`(5) {
        present(value) => { if value != 5 { return 18 } },
        none => { return 19 }
    }
    if !set.is_empty() { return 20 }
    0
}
