// expect-error: ownership 2:81 moved
fn main() { let first=core::sync::atomic::AtomicU32::new(42); let second=first; first.load(core::sync::atomic::Ordering::Relaxed) as i32 }
