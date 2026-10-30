
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; } } }
import core.iter.Iterator;
type Counter { n: i32; max: i32 }
extend Counter implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
type Box<T> { v: T }
type Mapped<I, F> { iter: I; f: F }
extend<B, I: Iterator, F: fn(I.(Iterator).Item): B> Mapped<I, F> implements Iterator {
    type Item = B
    mut fn next(): B? {
        match self.iter.next() { present(x) => present(self.f(x)), none => none }
    }
}
fn map<B, I: Iterator, F: fn(I.(Iterator).Item): B>(it: take I, f: take F): Mapped<I, F> { Mapped(it, f) }
type Take<I> { iter: I; n: usize }
extend<T, I: Iterator<Item = T>> Take<I> implements Iterator {
    type Item = T
    mut fn next(): T? {
        if self.n == 0usize { return none }
        self.n -= 1usize
        self.iter.next()
    }
}
fn wrap<I: Iterator>(it: take I, w: take Box<I.(Iterator).Item>): Box<I.(Iterator).Item> { w }
fn apply<B, F: fn(i32): B>(f: take F): B { f(1) }
fn apply_ptr<B>(f: fn(i32): B, x: i32): B { f(x) }
fn plus(x: i32): i32 { x + 1 }
fn main(): i32 {
    let w = wrap(Counter(0, 1), Box(5))
    var m = map(Take(Counter(0, 10), 4usize), fn(x: i32): i32 { x * 10 })
    var total = 0
    for x in mut m { total += x }
    let a = apply(fn(x: i32): i32 { x + 1 })
    let b = apply_ptr(plus, 1)
    let c = apply(fn(x: i32) { x * 3 })
    if w.v == 5 && total == 60 && a == 2 && b == 2 && c == 3 { 0 } else { 1 }
}
