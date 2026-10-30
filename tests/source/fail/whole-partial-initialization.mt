// expect-error: type 3:45 binding 'p' may be uninitialized
copy type P { x: i32; y: i32 }
fn main() { let p: P; p.x = 1; let copied = p; 0 }
