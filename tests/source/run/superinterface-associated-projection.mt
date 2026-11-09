interface Source {
    type Item
    mut fn next(): Self.Item?
}
interface Sized: Source {
    fn remaining(): usize
}
type Count { value: i32; limit: i32 }
extend Count implements Source {
    type Item = i32
    mut fn next(): i32? {
        if self.value >= self.limit { return none }
        self.value += 1
        present(self.value)
    }
}
extend Count implements Sized {
    fn remaining(): usize { (self.limit - self.value) as usize }
}
type Mapped<I, F> { inner: I; f: F }
extend<I: Sized, F: fn(read I.Item): i32> Mapped<I, F> {
    mut fn total(): i32 {
        var sum = 0
        while let present(item) = self.inner.next() { sum += (self.f)(read item) }
        sum
    }
    fn left(): usize { self.inner.remaining() }
}
fn first<I: Sized>(mut source: I): I.Item? { source.next() }
fn main(): i32 {
    var counter = Count(0, 3)
    match first(mut counter) { present(1) => {}, _ => { return 1 } }
    var mapped = Mapped(counter, fn(read value: i32): i32 { value * 10 })
    if mapped.left() != 2usize { return 2 }
    if mapped.total() != 50 { return 3 }
    0
}
