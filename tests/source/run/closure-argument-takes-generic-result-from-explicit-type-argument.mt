
fn apply<B>(f: take fn(i32): B): B { f(1) }
type Holder<P> { p: P }
fn main(): i32 {
    let a = apply<i32>(fn(x: i32): i32 { x + 41 })
    let h = Holder<fn(i32): bool>(fn(x: i32): bool { x % 2 == 0 })
    if a != 42 || !h.p(4) || h.p(3) { return 1 }
    0
}
