// expect-error: type 3:23 expected i32, found bool
copy type P { x: i32 }
fn main() { let p = P(true); 0 }
