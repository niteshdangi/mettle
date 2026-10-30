import alloc.btree;
import alloc.string;

fn main(): i32 {
    var m = btree.new<string.String, i32>()
    let a = m.insert(string.from_text("a"), 1)
    let b = m.insert(string.from_text("b"), 2)
    var n = 0
    match m.get("b") { present(v) => { n += *v }, none => {} }
    if m.contains_key("a") { n += 10 }
    match take m.get_mut("a") { present(v) => { *v = 5 }, none => {} }
    match m.remove("a") { present(v) => { n += v }, none => {} }
    if !m.contains_key("a") { n += 100 }
    if n == 2 + 10 + 5 + 100 { 0 } else { 1 }
}
