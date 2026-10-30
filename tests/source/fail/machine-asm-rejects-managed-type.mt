// expect-error: assembly 3:44 operand type
copy type Pair { first: i32; second: i32 }
fn main() { let pair = Pair(1,2); unsafe { asm!("/* {value} */",value = in(reg) pair) }; 0 }
