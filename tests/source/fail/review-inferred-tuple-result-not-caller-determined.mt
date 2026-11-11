// expect-error: type 4:5 expected (i64, i32), found (i32, i32)
fn value() { (1, 2) }
fn main(): i32 {
    let n: (i64, i32) = value()
    0
}
