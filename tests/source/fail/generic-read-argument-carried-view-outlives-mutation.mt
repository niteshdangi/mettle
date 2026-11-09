// expect-error: ownership 6:65 live read loan
import core.clone.Clone
type W<K> { v: K }
type H<region r> { v: read i32 from r }
extend<region r> H<region r> implements Clone { fn clone(): H<region r> { H(self.v) } }
fn main(): i32 { var x = 5; let h = H(read x); let w = wrap(h); x = 6; *w.v.v - 5 }
fn wrap<K: Clone>(read a: K): W<K> { W(a.clone()) }
