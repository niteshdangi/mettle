// expect-error: constant 2:29 integer overflow
const fn big(x: i32): i32 { x * 2 }
static V: i32 = big(2147483647);
fn main(): i32 { 0 }
