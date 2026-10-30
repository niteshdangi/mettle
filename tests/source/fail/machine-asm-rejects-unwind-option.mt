// expect-error: assembly 2:22 unsupported assembly option
fn main() { unsafe { asm!("nop",options(may_unwind)) }; 0 }
