// A `read K` argument whose instantiation carries no views is not a source of
// a result that only mentions `K`, so a temporary argument may end early.
type S<K> { v: K }
type R<region r, K> { s: read S<K> from r }
extend<K> S<K> { fn find(read a: K): R<region self, K> { R(read self) } }
fn main(): i32 { let s = S<i32>(1); let r = s.find(1 + 0); r.s.v - 1 }
