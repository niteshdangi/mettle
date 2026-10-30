// expect-error: assembly 2:22 NUL
fn main() { unsafe { asm!("nop\0",options(raw)) }; 0 }
