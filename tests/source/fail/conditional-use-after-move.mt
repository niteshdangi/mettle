// expect-error: ownership 3:63 moved
type P { x: i32 }
fn choose(flag: bool) { let p = P(42); if flag { let q = p }; p.x }
fn main() { choose(false) }
