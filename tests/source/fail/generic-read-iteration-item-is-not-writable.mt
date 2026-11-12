// expect-error: ownership 9:66 cannot write through a read parameter

module core { pub module iter {
  pub interface Iterator { type Item; mut fn next(): Self.Item?; }
  pub interface Iterable { type Item; type Iter<region r>: Iterator<Item = read Self.Item from r>; fn iter<region r>(receiver read self: Self from r): Self.Iter<region r>; }
} }
import core.iter.Iterable

fn poke<C: Iterable<Item = i32>>(read c: C): Unit { for x in c { *x = 5 } }
fn main(): i32 { 0 }
