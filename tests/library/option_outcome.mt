import core.option
import core.outcome
fn dbl(take x: i32): i32 { x * 2 }
fn bigger(read x: i32): bool { x > 5 }
fn half(take x: i32): (Outcome<i32, i32>) { if x % 2 == 0 { success(x / 2) } else { failure(x) } }
fn zero(): i32 { 0 }
fn neg(take e: i32): i32 { -e }
fn s(v: i32): i32? { present(v) }
fn z(): i32? { none }
fn main(): i32 {
    var a: i32? = present(4)
    var n: i32? = none
    if !a.is_present() || a.is_none() || n.is_present() || !n.is_none() { return 1 }
    match take a.as_mut() { present(v) => { *v = 5 }, none => { return 2 } }
    match a.as_view() { present(v) => { if *v != 5 { return 3 } }, none => { return 3 } }
    if s(5).map(dbl).unwrap() != 10 { return 4 }
    if z().map(dbl).unwrap_or(-1) != -1 { return 5 }
    if z().unwrap_or_else(zero) != 0 { return 6 }
    if s(5).filter(bigger).is_present() || !s(6).filter(bigger).is_present() { return 7 }
    let t = a.take_value()
    if a.is_present() || t.unwrap() != 5 { return 8 }
    let old = a.replace(9)
    if old.is_present() || a.expect("x") != 9 { return 9 }
    match z().ok_or(7) { success(v) => { return 10 }, failure(e) => { if e != 7 { return 11 } } }
    let r: (Outcome<i32, i32>) = success(8)
    if r.map(dbl).unwrap() != 16 { return 12 }
    if half(7).is_success() || half(7).err().unwrap() != 7 { return 14 }
    if half(8).and_then(half).unwrap() != 2 { return 15 }
    if half(3).map_err(neg).unwrap_or_else(neg) != 3 { return 16 }
    if half(8).ok().unwrap() != 4 { return 17 }
    0
}
