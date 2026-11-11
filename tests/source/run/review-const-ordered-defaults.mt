const BASE: i32 = 7
const fn total(a: i32 = BASE, b: i32 = a + 1, c: i32 = b + 1): i32 {
    a + b + c
}
const fn caller(): i32 {
    let BASE = 100
    total()
}
const DEFAULTS: i32 = caller()
const NAMED: i32 = total(c: 20, a: 10)
fn main(): i32 {
    if DEFAULTS == 24 && NAMED == 41 { 0 } else { 1 }
}
