// expect-error: constant 2:1 cycle
const A: i32 = B + 1
const B: i32 = A + 1
static V: i32 = A
fn main(): i32 { 0 }
