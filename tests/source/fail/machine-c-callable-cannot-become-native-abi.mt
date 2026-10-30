// expect-error: type 3:13 found extern "C" fn
extern "C" fn callback(value: i32): i32 { value }
fn main() { let p: fn(i32): i32 = callback; p(0) }
