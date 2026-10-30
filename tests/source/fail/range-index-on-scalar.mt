// expect-error-count: 1
// expect-error: type 3:42 range indexing requires an array, slice or a type
fn main(): i32 { let x = 5; let y = read x[1..2]; 0 }
