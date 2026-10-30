// expect-error: type 3:51 binding 'p.x' may be uninitialized
copy type P { x: i32 }
fn choose(b: bool) { let p: P; if b { p.x = 42 }; p.x }
fn main() { choose(true) }
