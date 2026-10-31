import alloc.hash_map
import core.hash.{BuildHasher, FnvBuilder}

fn main(): i32 {
    var values = hash_map.set_new<i32>()
    match values.replace(3) {
        present(_) => { return 1 },
        none => {}
    }
    if !values.contains(3) { return 2 }
    match values.replace(3) {
        present(old) => { if old != 3 { return 3 } },
        none => { return 4 }
    }
    let builder = FnvBuilder()
    if builder.hash_one(1) != builder.hash_one(1) { return 5 }
    if builder.hash_one(1) == builder.hash_one(2) { return 6 }
    0
}
