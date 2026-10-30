// expect-error-count: 1
// expect-error: type 3:52 expected usize, found i32
fn main(): i32 { let a = [1, 2, 3]; let y = read a[1i32..2]; 0 }
