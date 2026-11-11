// expect-error: ownership 11:24 access or storage lifetime conflicts with a live read loan
// expect-error: ownership 16:24 access or storage lifetime conflicts with a live read loan
// expect-error-count: 2
import alloc.btree
import alloc.hash_map

fn main(): i32 {
    var hashed = hash_map.new<i32, i32>()
    let pending = hashed.entry(7)
    let key = pending.key()
    core.mem.drop(take pending)
    let first = *key
    var ordered = btree.new<i32, i32>()
    let entry = ordered.entry(77)
    let other = entry.key()
    core.mem.drop(take entry)
    first + *other
}
