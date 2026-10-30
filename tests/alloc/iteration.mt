import alloc::vec::Vec;
import core::iter::{Iterator, IntoIterator, DoubleEndedIterator};

fn main(): i32 {
    var v = alloc::vec::new::<i32>()
    v.push(1); v.push(2); v.push(3)
    var s = 0
    for x in read v { s += *x }
    if s != 6 { return 1 }
    for x in mut v { *x += 10 }
    var t = 0
    for x in read v { t += *x }
    if t != 36 { return 2 }
    var it = v.into_iter()
    match it.next_back() { present(e) => { if e != 13 { return 3 } }, none => { return 4 } }
    var u = 0
    for e in take it { u += e }
    if u != 23 { return 5 }
    0
}
