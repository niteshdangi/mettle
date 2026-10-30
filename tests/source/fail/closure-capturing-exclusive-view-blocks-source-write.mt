// expect-error: ownership 8:5 live exclusive loan

fn main(): i32 {
    var v = 1
    let m = mut v
    var f = fn(): Unit { *m += 1 }
    f()
    v = 3
    f()
    0
}
