// expect-error: assembly 2:35 noreturn
fn main() { var value=0; unsafe { asm!("/* {out} */",out = out(reg) value, options(noreturn)) } }
