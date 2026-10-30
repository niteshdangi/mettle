import alloc.vec.List
import core.iter.{Iterator, OwnedIterable}
type D { c: ptr<mut i32>; id: i32
    drop { unsafe { *self.c += self.id } } }
fn main(): i32 {
    var v = alloc.vec.new<i32>()
    var i = 0
    while i < 100 { v.push(i * 3 % 17); i += 1 }
    if v.len() != 100usize { return 1 }
    v.sort()
    var k = 1usize
    while k < 100usize { if v[k - 1usize] > v[k] { return 2 }; k += 1usize }
    v.dedup()
    if v.len() != 17usize { return 3 }
    if !v.contains(5) || v.contains(99) { return 4 }
    v.insert(0usize, 77)
    if v[0usize] != 77 { return 5 }
    let x = v.remove(0usize)
    let y = v.swap_remove(0usize)
    if x != 77 || y != 0 || v.len() != 16usize { return 6 }
    v.truncate(3usize)
    let s = v.as_slice()
    if s.len() != 3usize { return 7 }
    var it = v.into_iter()
    var sum = 0
    while true { match it.next() { present(e) => { sum += e }, none => { break } } }
    if sum != 16 + 1 + 2 { return 8 + sum }
    var n = 0
    {
        var d = alloc.vec.new<D>()
        d.push(D(core.ptr.from_mut(n), 1))
        d.push(D(core.ptr.from_mut(n), 10))
        d.push(D(core.ptr.from_mut(n), 100))
        d.truncate(2usize)
        if n != 100 { return 20 }
    }
    if n != 111 { return 21 }
    0
}
