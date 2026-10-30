
type List<T> { a: T; n: usize }
enum Opt<T> { Some(T), Nothing }
fn nothing<T>(): Opt<T> { Opt.Nothing }
type Slot<K> { v: K? }
extend<K> Slot<K> {
    static fn empty(): Slot<K> { Slot(none) }
}
fn main(): i32 {
    let s: Opt<i32> = nothing()
    let t: Opt<i32> = Opt<i32>.Nothing
    let e: Slot<i32> = Slot.empty()
    match s { Opt.Nothing => 0, Opt.Some(_) => 1 }
}
