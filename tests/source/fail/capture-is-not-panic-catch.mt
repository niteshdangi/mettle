// expect-error: effects 2:25 requires a typed throwing
fn main() { let value = capture (1 / 0); 0 }
