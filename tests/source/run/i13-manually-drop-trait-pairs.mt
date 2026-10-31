// ManuallyDrop forwards comparison, hashing, cloning and defaults to its payload
// and never destroys the payload on its own.
import core.hash.{Hash, Hasher}
fn hash_of(value: read core.mem.ManuallyDrop<i32>): u64 {
    var hasher = core.hash.fnv1a()
    value.hash(mut hasher)
    hasher.finish()
}
fn make<T: core.default.Default>(): T { T.(core.default.Default).default() }
fn main(): i32 {
    let a = core.mem.ManuallyDrop.new(3)
    let b = core.mem.ManuallyDrop.new(4)
    let copy = a.clone()
    if a != copy || a == b { return 1 }
    if !(a < b) || b.cmp(read a).is_lt() { return 2 }
    if hash_of(a) != hash_of(copy) { return 3 }
    let zero = make<core.mem.ManuallyDrop<i32>>()
    if *zero.get_ref() != 0 { return 4 }
    if *a.get_ref() != 3 { return 5 }
    0
}
