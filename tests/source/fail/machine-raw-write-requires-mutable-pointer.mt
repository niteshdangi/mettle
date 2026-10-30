// expect-error: type 2:74 invalid primitive operation
fn main() { let value = 42; let p = core::ptr::from_ref(value); unsafe { p.write(1) }; 0 }
