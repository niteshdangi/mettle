import alloc.hash_map.HashMap;
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
    let r = m.or_insert(5000, 9i64)
    0
}
