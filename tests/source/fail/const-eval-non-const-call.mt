// expect-error: constant 3:17 requires a validated constant expression
fn runtime(x: i32): i32 { x + 1 }
static V: i32 = runtime(1);
fn main(): i32 { 0 }
