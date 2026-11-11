// expect-error: constant 2:34 division by zero
const fn bad(): i32 throws i32 { 1 / 0 }
static VALUE: Outcome<i32, i32> = capture bad()
fn main(): i32 { 0 }
