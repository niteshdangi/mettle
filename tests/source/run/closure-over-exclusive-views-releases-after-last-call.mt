
type Cur<region r> { p: mut i32 from r }
fn main(): i32 {
    var v = 1
    var cur = Cur(mut v)
    var slot = fn(): mut i32 { mut *cur.p }
    let a = slot()
    *a = 5
    let b = slot()
    *b += 1
    v += 1
    if v == 7 { 0 } else { 1 }
}
