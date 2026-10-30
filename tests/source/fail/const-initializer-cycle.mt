// expect-error: constant 2:1 cycle in required static initialization
const A: i32 = B;
const B: i32 = A;
fn main(): i32 { A }
