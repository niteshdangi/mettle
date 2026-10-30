// expect-error: attribute 2:26 exactly naked_asm
@naked unsafe extern "C" fn invalid(value: i32): i32 { value }
fn main() { 0 }
