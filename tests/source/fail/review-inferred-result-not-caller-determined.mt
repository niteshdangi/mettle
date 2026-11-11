// expect-error: type 4:5 expected i64, found i32
fn value() { 1 }
fn main(): i32 {
    let n: i64 = value()
    0
}
