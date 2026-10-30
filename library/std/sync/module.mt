// Thread synchronization built on the hosted runtime's pthread shims
// (`runtime/thread.cpp`). Locks yield guards that borrow the lock, cannot
// cross threads, and report poisoning when released by an unwinding panic.
// Race freedom here is not a promise of fairness or deadlock freedom.
pub module mutex
pub module rwlock
pub module condvar
pub module barrier
pub module once
pub module mpsc
pub module tls
