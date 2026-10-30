// expect-error: type 3:33 only integer and bool constants
const A: (i32, i32) = (1, 2)
fn main(): i32 { match (1, 2) { A => 0 } }
