// arch: x86_64
// expect-error: assembly 3:22 explicit register
fn main() { unsafe { asm!("nop",out(x87_reg) _) }; 0 }
