// expect-error: type 2:37 unsized value requires a view
fn main(): i32 { let a = [1, 2, 3]; let y = a[1..2]; 0 }
