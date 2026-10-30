// expect-error: assembly 2:22 modifier
fn main() { unsafe { asm!("/* {value:z} */",value = in(reg) 1) }; 0 }
