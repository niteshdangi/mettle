// expect-error: type 4:13 expected A, found B
copy type A { x: i32 }
copy type B { x: i32 }
fn main() { let x: A = B(1); 0 }
