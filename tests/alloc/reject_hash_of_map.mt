// expect-error: type
import alloc.hash_map
import core.hash.hash_one

fn main(): i32 {
    let m = hash_map.new<i32, i32>()
    hash_one(m) as i32
}
