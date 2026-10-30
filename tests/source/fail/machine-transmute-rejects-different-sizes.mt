// expect-error: type 2:34 invalid primitive operation or operand types
fn main() { let value = unsafe { core::mem::transmute::<u64>(1u32) }; 0 }
