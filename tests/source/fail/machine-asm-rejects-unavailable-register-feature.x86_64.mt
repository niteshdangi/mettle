// arch: x86_64
// expect-error: assembly 3:22 required feature
fn main() { unsafe { asm!("/* {value} */",value = out(ymm_reg) _,options(nomem)) }; 0 }
