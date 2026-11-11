// expect-error: type 7:5 unsatisfied interface obligation: no implementation of 'any Hash' is available for 'Map<i32, i32, Global, DefaultHashBuilder>'
import alloc.hash_map
import core.hash.hash_one

fn main(): i32 {
    let m = hash_map.new<i32, i32>()
    hash_one(m) as i32
}
