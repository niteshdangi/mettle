// expect-error: type 2:45 binding 'x' may be uninitialized
fn f(b: bool) { let x: i32; if b { x = 1 }; x }
fn main() { 0 }
