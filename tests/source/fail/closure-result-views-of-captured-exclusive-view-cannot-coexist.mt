// expect-error: ownership 10:5 live exclusive loan

type Cur<region r> { p: mut i32 from r }
fn main(): i32 {
    var v = 1
    var cur = Cur(mut v)
    var f = fn(): mut i32 { mut *cur.p }
    let a = f()
    let b = f()
    *a = 1
    *b = 2
    0
}
