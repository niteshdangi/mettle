// expect-exit: trap
fn main(): i32 { let value=core.sync.atomic.AtomicU32.new(42); let outcome=value.compare_exchange(42,1,core.sync.atomic.Ordering.SeqCst,core.sync.atomic.Ordering.Release); 0 }
