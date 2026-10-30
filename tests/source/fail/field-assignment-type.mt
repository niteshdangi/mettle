// expect-error: type 3:27 expected i32, found bool
copy type P { x: i32 }
fn main() { var p = P(0); p.x = true; 0 }
