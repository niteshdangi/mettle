// expect-error: type 3:23 binding 'p.x' may be uninitialized
copy type P { x: i32 }
fn main() { let p: P; p.x }
