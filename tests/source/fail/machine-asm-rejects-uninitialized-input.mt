// expect-error: type 2:74 uninitialized
fn main() { var value:i32; unsafe { asm!("/* {input} */",input = in(reg) value) }; 0 }
