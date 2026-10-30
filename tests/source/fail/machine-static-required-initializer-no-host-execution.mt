// expect-error: constant 2:47 validated constant
fn compute(): i32 { 42 }; static VALUE: i32 = compute(); fn main() { 0 }
