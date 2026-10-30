// expect-error: ownership 3:60 moved
type P { x: i32 }
fn main() { var p = P(1); var n = 0; while n < 2 { let q = p; n += 1 }; 0 }
