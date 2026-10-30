// expect-error: type 3:48 immutable binding 'p.x'
copy type P { x: i32 }
fn main() { let p: P; var n = 0; while n < 2 { p.x = n; n += 1 }; 0 }
