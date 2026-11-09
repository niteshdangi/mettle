// Each generic instance of an indirect call through `fn(i32): W<T>` uses its
// own signature, and a generic unit variant path infers its arguments even
// when inherent associated constants exist.
type W<T> { v: T }
type H<T> { f: fn(i32): W<T> }
fn call<T>(read h: H<T>): W<T> { (h.f)(1) }
fn gi(x: i32): W<i32> { W(x) }
fn gb(x: i32): W<bool> { W(x == 1) }
type Limits { }
extend Limits { const MAX: i32 = 3 }
enum P<T> { Ready(T), Pending }
fn f(x: bool): P<i32> { if x { P.Ready(Limits.MAX) } else { P.Pending } }
fn main(): i32 {
    if !call(H(gb)).v { return 2 }
    if call(H(gi)).v != 1 { return 3 }
    match take f(false) { P.Ready(v) => v, P.Pending => match take f(true) { P.Ready(v) => v - 3, P.Pending => 1 } }
}
