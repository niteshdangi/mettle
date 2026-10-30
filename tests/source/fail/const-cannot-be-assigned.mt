// expect-error: type 3:18 cannot assign immutable binding
const A: i32 = 1;
fn main(): i32 { A = 2; 0 }
