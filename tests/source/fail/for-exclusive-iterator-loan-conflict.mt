// expect-error: ownership 6:49 live exclusive loan
module core { pub module iter { pub interface Iterator { type Item; mut fn next(): Self.Item?; } } }
type C { n: i32 }
extend C implements core.iter.Iterator { type Item = i32
 mut fn next(): i32? { none } }
fn main(): i32 { var c = C(0); for x in mut c { c.n = 1 }; 0 }
