// expect-error: type 2:24 cannot assign immutable binding 'x' more than once
fn main() { let x = 1; x = 2; x }
