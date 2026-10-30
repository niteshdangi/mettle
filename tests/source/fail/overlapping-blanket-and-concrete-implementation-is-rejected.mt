// expect-error: type 26:1 overlapping implementations cannot be selected by order
module core {
    pub module iter {
        pub interface Iterator { type Item; mut fn next(): Self.Item?; }
        pub interface OwnedIterable: Sized { type Item; type IntoIter: Iterator; fn into_iter(receiver self: take Self): Self.IntoIter; }
        extend<I: Iterator> I implements OwnedIterable {
            type Item = I.Item
            type IntoIter = I
            fn into_iter(receiver self: take Self): I { self }
        }
    }
}
type Counter { n: i32; max: i32 }
extend Counter implements core.iter.Iterator {
    type Item = i32
    mut fn next(): i32? {
        if self.n < self.max { let v = self.n; self.n += 1; present(v) } else { none }
    }
}
type Bag { max: i32 }
extend Bag implements core.iter.OwnedIterable {
    type Item = i32
    type IntoIter = Counter
    fn into_iter(receiver self: take Self): Counter { Counter(0, self.max) }
}
extend Counter implements core.iter.OwnedIterable {
    type Item = i32
    type IntoIter = Counter
    fn into_iter(receiver self: take Self): Counter { self }
}
fn main(): i32 { 0 }
