// arch: aarch64
// expect-error: assembly 3:22 reserved
fn main() { unsafe { asm!("nop",out("x18") _) }; 0 }
