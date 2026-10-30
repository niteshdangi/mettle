// arch: aarch64
// expect-error: assembly 3:22 conflicting
fn main() { unsafe { asm!("nop",in("x0") 1i64,out("w0") _) }; 0 }
