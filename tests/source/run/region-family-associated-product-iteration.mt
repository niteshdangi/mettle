
module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Iter<region r>; fn iter<region r>(receiver self: read Self from r): Self.Iter<region r>; }
} }
import core.iter.Iterator
import core.iter.Iterable
type Bag { a: i32; b: i32 }
type BagIter<region r> { bag: read Bag from r; i: i32 }
extend<region r> BagIter<region r> implements Iterator {
    type Item = i32
    mut fn next(): i32? {
        let i = self.i
        self.i += 1
        if i == 0 { present(self.bag.a) } else if i == 1 { present(self.bag.b) } else { none }
    }
}
extend Bag implements Iterable {
    type Iter<region r> = BagIter<region r>
    fn iter<region r>(receiver self: read Self from r): BagIter<region r> { BagIter(read self, 0) }
}
fn main(): i32 {
    let bag = Bag(3, 4)
    var t = 0
    for x in bag { t += x }
    t - 7
}
