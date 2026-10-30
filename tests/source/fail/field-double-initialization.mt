// expect-error: type 3:32 immutable binding 'p.x'
copy type P { x: i32 }
fn main() { let p: P; p.x = 1; p.x = 2; 0 }
