// expect-error: constant 4:18 outside its type range
// expect-error: type 4:18 outside the usize range
// expect-error-count: 2
const N: usize = 18446744073709551616;
fn main(): i32 { 0 }
