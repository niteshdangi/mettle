// expect-error: feature 2:23 lock-free alias
fn main() { let value=core::sync::atomic::AtomicU128::new(0); 0 }
