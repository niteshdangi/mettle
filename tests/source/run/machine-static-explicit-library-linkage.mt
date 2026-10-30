
@link("m")
extern "C" { unsafe fn abs(value: i32): i32; }
fn main() { if unsafe { abs(-42) } == 42 { 0 } else { 1 } }
