// expect-error: parse 2:56 ranges do not chain
fn main(): i32 { let a = [1, 2, 3]; let y = read a[3..1..2]; 0 }
