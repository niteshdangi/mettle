// arch: aarch64
// expect-error: assembly 3:22 explicit register
fn main() { unsafe { asm!("nop",out(preg) _) }; 0 }
