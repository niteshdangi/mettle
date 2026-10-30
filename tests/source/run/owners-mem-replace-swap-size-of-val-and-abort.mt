
type P { a: i32; b: i64 }
type H<T> { v: T }
fn exchange(dest: mut i32, v: i32): i32 { core::mem::replace(dest, v) }
fn keep(slot: mut H<read i32>, v: take H<read i32>): H<read i32> from (slot, v) {
    core::mem::replace(slot, v)
}
fn die(): Never { core::intrinsics::abort() }
fn main() {
    var x = 5
    var y = 7
    let old = core::mem::replace(x, 9)
    core::mem::swap(x, y)
    var p = P(1, 2)
    var q = P(3, 4)
    core::mem::swap(p, q)
    let old2 = core::mem::replace(p, P(10, 20))
    var z = 1
    let r = exchange(z, 2)
    let words = [1u32, 2u32, 3u32]
    let a = 1
    let b = 2
    var first = H(read a)
    let second = H(read b)
    let previous = keep(first, second)
    if old != 5 { return 1 }
    if x != 7 || y != 9 { return 2 }
    if p.a != 10 || q.a != 1 || old2.a != 3 { return 3 }
    if z != 2 || r != 1 { return 4 }
    if core::mem::size_of_val(words) != 12usize { return 5 }
    if core::mem::align_of_val(p) != 8usize { return 6 }
    if *previous.v != 1 || *first.v != 2 { return 7 }
    if x == 0 { die() }
    0
}
