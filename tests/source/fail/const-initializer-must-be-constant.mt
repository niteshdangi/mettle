// expect-error: constant 3:16 validated constant expression
fn f(): i32 { 3 }
const X: i32 = f()
fn main(): i32 { X }
