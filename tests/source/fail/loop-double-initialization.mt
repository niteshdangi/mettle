// expect-error: type 2:50 cannot assign immutable binding 'x' more than once
fn main() { let x: i32; var n = 0; while n < 2 { x = n; n += 1 }; 0 }
