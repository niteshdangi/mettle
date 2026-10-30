// expect-error: type 2:25 binding 'x' may be uninitialized
fn main() { var x: i32; x += 1; x }
