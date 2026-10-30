// expect-error: ownership 2:49 exclusive borrow requires a mutable place
fn main(): i32 { let a = [1, 2, 3]; let y = mut a[1..2]; 0 }
