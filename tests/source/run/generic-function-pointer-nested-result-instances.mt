// Each generic instance of an indirect call through `fn(i32): W<T>` uses its
// own contract signature.
type W<T> { v: T }
type H<T> { f: fn(i32): W<T> }
fn call<T>(h: read H<T>): W<T> { (h.f)(1) }
fn gi(x: i32): W<i32> { W(x) }
fn gb(x: i32): W<bool> { W(x == 1) }
fn main(): i32 {
    let a = H(gi)
    let b = H(gb)
    if !call(b).v { return 2 }
    call(a).v - 1
}
