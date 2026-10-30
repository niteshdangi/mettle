// expect-error: constant 2:39 division by zero
const fn ratio(a: i32, b: i32): i32 { a / b }
static V: i32 = ratio(1, 0)
fn main(): i32 { 0 }
