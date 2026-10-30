// arch: x86_64
// expect-error: assembly 3:22 conflicting
fn main() { unsafe { asm!("nop",in("rax") 1i64,out("eax") _) }; 0 }
