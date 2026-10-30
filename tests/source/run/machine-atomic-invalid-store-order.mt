// expect-exit: trap
fn main(): i32 { let value=core::sync::atomic::AtomicU32::new(42); value.store(1,core::sync::atomic::Ordering::Acquire); 0 }
