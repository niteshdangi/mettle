// expect-error: type 3:33 expected mut i32, found read i32
// expect-help: this position requires a mutable view; pass `mut value`
fn main(): i32 { var count = 1; let view: mut i32 = read count; 0 }
