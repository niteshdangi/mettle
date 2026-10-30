
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self.Item?; } } }
import core.iter.Iterator
type Counter { n: i32; max: i32 }
extend Counter implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
fn sum<T, I: Iterator<Item = T>>(it: take I, first: take T): T {
    var iter = it
    var acc = first
    while true { match take iter.next() { present(x) => { acc = x }, none => { break } } }
    acc
}
fn main(): i32 {
    let last = sum(Counter(0, 4), 0)
    if last != 3 { return 1 }
    0
}
