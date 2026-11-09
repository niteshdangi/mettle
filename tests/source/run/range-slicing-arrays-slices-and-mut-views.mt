
fn total(read v: [i32]): i32 { var t = 0; for x in v { t += x }; t }
fn main(): i32 {
    var a: [i32; 5] = [1, 2, 3, 4, 5]
    let s: read [i32] = read a[1..4]
    let whole: read [i32] = read a[..]
    let head: read [i32] = read a[..=1]
    let tail: read [i32] = read a[3..]
    if total(s) != 9 || whole.len() != 5 || head.len() != 2 || tail.len() != 2 { return 1 }
    let m: mut [i32] = mut a[1..3]
    m[0] = 20
    let inner: read [i32] = read m[1..]
    if inner.len() != 1 || a[1] != 20 { return 2 }
    0
}
