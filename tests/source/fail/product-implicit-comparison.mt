// expect-error: type 3:16 comparison interface
copy type P { x: i32 }
fn main() { if P(1) == P(1) { 0 } else { 1 } }
