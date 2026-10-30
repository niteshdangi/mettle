// expect-exit: 43
type Vec<T> { a: T; n: usize }
enum Opt<T> { Some(T), Nothing }
fn nothing<T>(): Opt<T> { Opt::Nothing }
fn id<T>(x: T): T { x }
type Slot<K> { v: K? }
extend<K> Slot<K> {
    static fn empty(): Slot<K> { Slot(none) }
}
fn main(): i32 {
    let s: Opt<i32> = nothing<i32>()
    let f = id<i32>
    let wrapped: Vec<Vec<i32>> = Vec(Vec(f(40), 1), 1)
    let a = 3
    let b = 4
    let cmp = if a < b { 1 } else { 0 }
    let base = match s { Opt::Nothing => 2, Opt::Some(_) => 0 }
    base + wrapped.a.a + cmp
}
