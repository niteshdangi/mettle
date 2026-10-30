// expect-error: unsafe 2:65 requires an unsafe block
fn main() { let value = 42; let p = core::ptr::from_ref(value); p.`read`() }
