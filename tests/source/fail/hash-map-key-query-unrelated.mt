// expect-error: type 6:8 unsatisfied interface obligation
import alloc.hash_map;
fn main(): i32 {
    var m = hash_map.new<i32, i32>()
    let old = m.insert(1, 1)
    if m.contains_key("a") { 1 } else { 0 }
}
