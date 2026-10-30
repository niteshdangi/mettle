
interface Less { fn less(other: read Self): bool; }
impl i32 implements Less { fn less(other: read i32): bool { self < other } }
unsafe fn ordered<T: Less>(p: ptr<mut T>, q: ptr<mut T>): bool {
    unsafe { read *p }.less(unsafe { read *q })
}
fn main(): i32 {
    var a = 1
    var b = 2
    let p = mut a as ptr<mut i32>
    let q = mut b as ptr<mut i32>
    if unsafe { ordered(p, q) } && !unsafe { ordered(q, p) } { 0 } else { 1 }
}
