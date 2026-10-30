// expect-error: type 3:21 argument count
copy type P { x: i32 }
fn main() { let p = P(); 0 }
