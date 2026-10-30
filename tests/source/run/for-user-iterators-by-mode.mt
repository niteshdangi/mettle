
module core {
    pub module iter {
        pub interface Iterator { type Item; mut fn next(): Self.Item?; }
        pub interface OwnedIterable: Sized { type Item; type IntoIter: Iterator; fn into_iter(receiver self: take Self): Self.IntoIter; }
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
fn main(): i32 {
    var total = 0
    for x in Counter(0, 5) { total += x }
    for x in take Bag(4) { total += x }
    var c = Counter(0, 3)
    for x in mut c { total += x * 100 }
    total - 316
}
