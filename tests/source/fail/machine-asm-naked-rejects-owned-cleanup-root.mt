// expect-error: attribute 3:42 requiring cleanup
@layout(C) type Owned { value:i32; drop {} }
@naked unsafe extern "C" fn invalid(take value: Owned) { naked_asm!("ret") }
fn main() { 0 }
