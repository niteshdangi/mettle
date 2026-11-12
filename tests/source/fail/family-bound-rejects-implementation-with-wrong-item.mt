// expect-error: type 11:1 associated item does not satisfy its interface bounds

module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>: Iterator<Item = read Self.Item from r>; fn iter<region r>(receiver read self: Self from r): Self.Iter<region r>; }
} }

type Bad { n: i32 }
extend Bad implements core.iter.Iterator { type Item = i32; mut fn next(): i32? { none } }
type Box { n: i32 }
extend Box implements core.iter.Iterable {
    type Item = i32
    type Iter<region r> = Bad
    fn iter<region r>(receiver read self: Self from r): Bad { Bad(0) }
}
fn main(): i32 { 0 }
