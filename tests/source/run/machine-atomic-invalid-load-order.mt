// expect-exit: trap
fn main(): i32 { let value=core.sync.atomic.AtomicU32.new(42); value.load(core.sync.atomic.Ordering.Release) as i32 }
