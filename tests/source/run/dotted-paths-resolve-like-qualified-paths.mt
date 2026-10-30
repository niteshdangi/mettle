// expect-exit: 58
module util {
    pub module deep { pub fn twice(x: i32): i32 { x * 2 } }
    pub fn inc(x: i32): i32 { x + 1 }
    pub type Counter { n: i32 }
    extend Counter {
        pub static fn start(n: i32): i32 { n }
    }
}
enum Opt<T> { Some(T), Nothing }
type Slot<K> { v: K? }
extend<K> Slot<K> {
    static fn empty(): Slot<K> { Slot(none) }
}
type Holder { util: i32 }
fn unwrap(o: Opt<i32>): i32 {
    match o { Opt.Some(x) => x, Opt.Nothing => 0 }
}
fn main(): i32 {
    let a: Opt<i32> = Opt.Some(40)
    let b = Opt<i32>.Nothing
    let c = Opt<i32>.Nothing
    let s: Slot<i32> = Slot.empty()
    let t = Slot<i32>.empty()
    let started = util.Counter.start(7)
    let incremented = util.inc(1)
    let doubled = util.deep.twice(3)
    let h = Holder(3)
    let util = h
    let shadowed = util.util
    unwrap(a) + unwrap(b) + unwrap(c) + incremented + doubled + started + shadowed
}
