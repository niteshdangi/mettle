import core.iter.Iterator;
import core.iter.Iterable;
import core.iter.MutableIterable;

type Bag { a: i32; b: i32 }
type BagIterMut<region r> { bag: mut Bag from r; at: i32 }
extend<region r> BagIterMut<region r> implements Iterator {
    type Item = mut i32 from r
    mut fn next(): (mut i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(mut self.bag.a) } else if i == 1 { present(mut self.bag.b) } else { none }
    }
}
extend Bag implements MutableIterable {
    type Item = i32
    type IterMut<region r> = BagIterMut<region r>
    fn iter_mut<region r>(receiver self: mut Self from r): BagIterMut<region r> { BagIterMut(mut self, 0) }
}
type BagIter<region r> { bag: read Bag from r; at: i32 }
extend<region r> BagIter<region r> implements Iterator {
    type Item = read i32 from r
    mut fn next(): (read i32 from r)? {
        let i = self.at
        self.at += 1
        if i == 0 { present(read self.bag.a) } else if i == 1 { present(read self.bag.b) } else { none }
    }
}
extend Bag implements Iterable {
    type Item = i32
    type Iter<region r> = BagIter<region r>
    fn iter<region r>(receiver self: read Self from r): BagIter<region r> { BagIter(read self, 0) }
}

// Generic code calls iterator methods on the bounded family directly.
fn first<C: Iterable>(c: read C): (read C.Item from c)? {
    var it = c.iter()
    it.next()
}
fn second<C: Iterable>(c: read C): (read C.Item from c)? {
    var it = c.iter()
    let skipped = it.next()
    it.next()
}

fn first_mut<C: MutableIterable>(c: mut C): (mut C.Item from c)? {
    var it = c.iter_mut()
    it.next()
}

fn main(): i32 {
    let bag = Bag(7, 9)
    match first(read bag) { present(x) => { if *x != 7 { return 1 } }, none => { return 2 } }
    match second(read bag) { present(x) => { if *x != 9 { return 3 } }, none => { return 4 } }
    var other = Bag(1, 2)
    match take first_mut(mut other) { present(x) => { *x += 1 }, none => { return 6 } }
    if other.a != 2 || other.b != 2 { return 5 }
    0
}
