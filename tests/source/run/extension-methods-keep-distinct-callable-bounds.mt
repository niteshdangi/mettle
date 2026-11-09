interface Source {
    type Item
    fn peek(): Self.Item
}
type Count { value: i32 }
extend Count implements Source {
    type Item = i32
    fn peek(): i32 { self.value }
}
type Mapped<I, F> { inner: I; f: F }
extend<I: Source, F: fn(read I.Item): i32> Mapped<I, F> {
    fn left(): i32 { 1 }
    fn apply(): i32 {
        let item = self.inner.peek()
        (self.f)(read item)
    }
}
fn main(): i32 {
    let mapped = Mapped(Count(4), fn(read value: i32): i32 { value * 10 })
    if mapped.left() != 1 { return 2 }
    if mapped.apply() != 40 { return 3 }
    0
}
