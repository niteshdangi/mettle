// expect-error: ownership 3:57 moved
copy type P { x: i32; y: i32 }
fn main() { let p = P(20,22); let x = take p.x; let q = p; 0 }
