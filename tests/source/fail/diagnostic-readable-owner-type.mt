// expect-error: type 3:53 expected heap i32, found heap bool
fn needs(value: heap i32) {}
fn main() { let value: heap bool = heap true; needs(value) }
