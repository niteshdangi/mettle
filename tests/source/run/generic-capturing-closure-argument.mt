fn apply<F: fn(i32): bool>(take f: F): bool { f(1) }
fn outer<T>(k: i32): bool { apply(fn(x: i32): bool { x == k }) }
type W<T> { v: i32 }
extend<T> W<T> {
    fn check<G: fn(i32): i32>(take g: G): bool { apply(fn(x: i32): bool { g(x) == self.v }) }
}
fn main(): i32 {
    let w = W<u8>(2)
    if outer<u8>(1) && w.check(fn(x: i32): i32 { x + 1 }) { 0 } else { 1 }
}
