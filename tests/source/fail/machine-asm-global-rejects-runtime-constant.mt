// expect-error-count: 1
// expect-error: type 3:43 unsupported operation in required constant
global_asm!("/* {value} */",value = const unknown)
fn main() { 0 }
