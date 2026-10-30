// expect-error: type 3:38 immutable binding 'p'
type P { x: i32 }
fn main() { let p = P(1); let q = p; p = P(2); 0 }
