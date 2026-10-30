// expect-error: feature 2:1 unwind metadata
@naked unsafe extern "C-unwind" fn invalid() { naked_asm!("ret") }
fn main() { 0 }
