// expect-error: region 9:70 view region or invariant payload

module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>: Iterator<Item = read Self.Item from r>; fn iter<region r>(receiver read self: Self from r): Self.Iter<region r>; }
} }
import core.iter.Iterable

fn leak<C: Iterable<Item = i32>>(read c: C): (read i32 from static)? { var it = c.iter(); it.next() }
fn main(): i32 { 0 }
