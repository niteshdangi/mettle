// expect-error: assembly 2:22 observable output
fn main() { unsafe { asm!("nop",options(pure,nomem)) }; 0 }
