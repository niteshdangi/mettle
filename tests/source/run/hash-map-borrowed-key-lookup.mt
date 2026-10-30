// A String-keyed map is searched with Text and owned keys without allocating;
// equal keys hash alike so growth, collisions and removals still find entries.
import alloc::hash_map;
import alloc::string;

fn key(i: u32): string::String {
    var s = string::from_text("k")
    s.push(((97u32 + i % 26u32) as u8) as char)
    s.push(((97u32 + i / 26u32) as u8) as char)
    s
}

fn main(): i32 {
    var m = hash_map::new::<string::String, i32>()
    var i = 0u32
    while i < 200u32 {
        let old = m.insert(key(i), i as i32)
        i += 1u32
    }
    var n = 0
    match m.get("kaa") { present(v) => { if *v == 0 { n += 1 } }, none => {} }
    match m.get("kbb") { present(v) => { if *v == 27 { n += 1 } }, none => {} }
    if !m.contains_key("k") { n += 1 }
    match take m.get_mut("kac") { present(v) => { *v = 70 }, none => {} }
    match m.get(key(52u32)) { present(v) => { if *v == 70 { n += 1 } }, none => {} }
    match m.remove("kbb") { present(v) => { if v == 27 { n += 1 } }, none => {} }
    if !m.contains_key("kbb") && m.len() == 199usize { n += 1 }
    var set = hash_map::set_new::<string::String>()
    let added = set.insert(string::from_text("x"))
    if set.contains("x") && !set.contains("y") && set.remove("x") { n += 1 }
    if n == 7 { 0 } else { n }
}
