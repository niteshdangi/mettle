// expect-error: type 2:73 invalid primitive operation or operand types
fn main() { let value = 0; let p = core::ptr::from_ref(value); unsafe { core::ptr::`copy`(p,p,1) }; 0 }
