import alloc.vec.List
import alloc.string.String
import core.clone.Clone
import core.cmp.{Ordering, Ord, PartialOrd}
import core.hash.{Hash, hash_one}
import core.fmt
import core.fmt.Debug

fn mk(a: i32, b: i32, c: i32): List<i32> {
    var v = alloc.vec.new<i32>()
    v.push(a); v.push(b); v.push(c)
    v
}
fn main(): i32 {
    let a = mk(1, 2, 3)
    let b = mk(1, 2, 3)
    let c = mk(1, 2, 4)
    if a != b || a == c { return 1 }
    if !(a < c) || a.cmp(read c) != Ordering.Less { return 2 }
    if hash_one(a) != hash_one(b) || hash_one(a) == hash_one(c) { return 3 }
    if a.len() != 3usize || (match a.first() { present(x) => *x != 1, none => true }) { return 4 }
    let m = read a[1..]
    if m.len() != 2usize || m[0] != 2 { return 5 }
    let k = a.clone()
    if k != a { return 6 }
    0
}
