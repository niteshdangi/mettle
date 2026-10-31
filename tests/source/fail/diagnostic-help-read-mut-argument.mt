// expect-error: type 4:34 expected mut i32, found read i32
// expect-help: this position requires a mutable view; pass `mut value`
fn needs(value: mut i32) {}
fn main() { let count = 1; needs(read count) }
