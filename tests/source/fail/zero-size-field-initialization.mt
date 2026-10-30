// expect-error: type 4:45 binding 'p' may be uninitialized
copy type E {}
copy type P { x: i32; tag: E }
fn main() { let p: P; p.x = 0; let copied = p; 0 }
