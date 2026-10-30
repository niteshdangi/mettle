// expect-error-count: 1
// expect-error: type 4:45 range indexing requires an array, slice or a type
type T { x: i32 }
fn main(): i32 { let a = T(1); let y = read a[1..2]; 0 }
