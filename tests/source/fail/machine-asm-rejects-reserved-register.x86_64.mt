// arch: x86_64
// expect-error: assembly 3:22 reserved
fn main() { unsafe { asm!("nop",out("rsp") _) }; 0 }
