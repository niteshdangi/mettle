// expect-error: attribute 3:37 requiring cleanup
@layout(C) type Owned { value:i32; drop {} }
@naked unsafe extern "C" fn invalid(value: take Owned) { naked_asm!("ret") }
fn main() { 0 }
