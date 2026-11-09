// profiles: debug release
import core.cmp.{PartialEq, PartialOrd, Ord, Ordering}
import core.default.Default
import core.clone.Clone
import core.hash.{Fnv1a, Hash, Hasher, fnv1a}
import core.iter.ExactSizeIterator
import alloc.vec

fn digest<T: Hash>(value: read T): u64 {
    var h = fnv1a()
    value.hash(mut h)
    h.finish()
}

fn main(): i32 {
    let a = [1i32, 2i32, 3i32]
    let b = [1i32, 2i32, 4i32]
    if a == b || !(a < b) || !(a != b) || a.cmp(read b) != Ordering.Less { return 1 }
    if a.partial_cmp(read a) != present(Ordering.Equal) { return 2 }
    if digest(read a) != digest(read a) { return 3 }

    let s: read [i32] = read a
    let t: read [i32] = read b
    if s == t || !(s < t) || s.cmp(read t) != Ordering.Less || !(s >= s) { return 4 }
    if s.is_empty() || s.len() != 3usize { return 5 }
    match s.first() { present(v) => { if *v != 1 { return 5 } }, none => { return 5 } }
    match s.last() { present(v) => { if *v != 3 { return 5 } }, none => { return 5 } }
    if !s.get(3usize).is_none() { return 6 }
    match s.get(1usize) { present(v) => { if *v != 2 { return 6 } }, none => { return 6 } }
    if !s.contains(read 2) || s.contains(read 9) { return 7 }
    if !s.starts_with(read [1i32, 2i32]) || !s.ends_with(read [2i32, 3i32]) { return 8 }
    match capture s.binary_search(read 2) { success(i) => { if i != 1usize { return 9 } }, failure(_) => { return 9 } }
    if !s.is_sorted() || s.split_at(1usize).0.len() != 1usize { return 10 }

    var v = [5i32, 3i32, 9i32, 1i32]
    let m: mut [i32] = mut v
    m.sort()
    if m[0usize] != 1 || m[3usize] != 9 { return 11 }
    m.reverse()
    if m[0usize] != 9 { return 12 }
    m.swap(0usize, 3usize)
    if m[0usize] != 1 { return 13 }
    m.fill(4)
    if m[2usize] != 4 || m[0usize] != 4 { return 14 }

    var n = 0usize
    for x in s.chunks(2usize) { n += x.len() }
    if n != 3usize || s.windows(2usize).len() != 2usize { return 15 }

    let tup = (1i32, 2i32)
    let tup2 = (1i32, 3i32)
    if tup == tup2 || !(tup < tup2) || tup.cmp(read tup2) != Ordering.Less { return 16 }
    if tup.clone() != tup || digest(read tup) == digest(read tup2) { return 17 }
    let d: (i32, bool) = (i32.(Default).default(), bool.(Default).default())
    if d != (0, false) { return 18 }
    if () != () || () > () || !(() >= ()) { return 19 }
    if digest(read ()) != digest(read ()) { return 20 }
    0
}
