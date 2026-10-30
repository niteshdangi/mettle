// expect-error: ownership 12:5 live exclusive loan

fn pick(c: mut i32, d: mut i32, p: ptr<mut i32>, flag: bool): mut i32 from (c, d) {
    let r = if flag { mut c } else { unsafe { mut *p } }
    r
}
fn main(): i32 {
    var a = 1
    var b = 2
    let p = mut b as ptr<mut i32>
    let x = pick(mut a, mut b, p, false)
    b = 5
    *x = 3
    0
}
