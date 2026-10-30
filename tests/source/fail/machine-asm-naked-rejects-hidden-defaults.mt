// expect-error: attribute 2:37 defaults
@naked unsafe extern "C" fn invalid(value:i32=42):i32 { naked_asm!("ret") }
fn main() { 0 }
