// expect-exit: 0
// profiles: debug release
// Blanket and auto-property evidence for sync types (Arc, locks, guards, Once, mpsc). Each call instantiates the
// blanket trait row for a hosted std type. Pairs the compiler cannot satisfy are
// listed as gaps at the end of main; negative impls are evidenced in tests/source/fail.
fn any_ok<T: unsized + core.any.Any>(): Unit {}
fn borrow_ok<T: unsized + core.borrow.Borrow<T>>(): Unit {}
fn owned_ok<T: core.borrow.ToOwned>(): Unit {}
fn from_ok<T: core.convert.From<T>>(): Unit {}
fn into_ok<T: core.convert.Into<T>>(): Unit {}
fn tryfrom_ok<T: core.convert.TryFrom<T>>(): Unit {}
fn tryinto_ok<T: core.convert.TryInto<T>>(): Unit {}
fn string_ok<T: alloc.string.ToString>(): Unit {}
fn send_ok<T: unsized + Transferable>(): Unit {}
fn sync_ok<T: unsized + Shareable>(): Unit {}
alias A_sync_Arc = alloc.arc.Arc<i32>
alias A_sync_Barrier = std.sync.barrier.Barrier
alias A_sync_Condvar = std.sync.condition.Condition
alias A_sync_Mutex = std.sync.mutex.Mutex<i32>
alias A_sync_MutexGuard = std.sync.mutex.MutexGuard<i32, region static>
alias A_sync_Once = std.sync.once.Once
alias A_sync_OnceLock = std.sync.once_lock.OnceLock<i32>
alias A_sync_RwLock = std.sync.rwlock.RwLock<i32>
alias A_sync_RwLockReadGuard = std.sync.rwlock.ReadGuard<i32, region static>
alias A_sync_RwLockWriteGuard = std.sync.rwlock.WriteGuard<i32, region static>
alias A_sync_Weak = alloc.arc.Weak<i32>
alias A_sync_atomic_Ordering = core.sync.atomic.Ordering
alias A_sync_mpsc_Receiver = std.sync.mpsc.Receiver<i32>
alias A_sync_mpsc_Sender = std.sync.mpsc.Sender<i32>
alias A_sync_mpsc_SyncSender = std.sync.mpsc.SyncSender<i32>
fn main(): i32 {
    // sync::Arc
    any_ok<A_sync_Arc>()
    borrow_ok<A_sync_Arc>()
    from_ok<A_sync_Arc>()
    tryfrom_ok<A_sync_Arc>()
    tryinto_ok<A_sync_Arc>()
    into_ok<A_sync_Arc>()
    send_ok<A_sync_Arc>()
    sync_ok<A_sync_Arc>()
    owned_ok<A_sync_Arc>()
    string_ok<A_sync_Arc>()
    // sync::Barrier
    any_ok<A_sync_Barrier>()
    borrow_ok<A_sync_Barrier>()
    from_ok<A_sync_Barrier>()
    tryfrom_ok<A_sync_Barrier>()
    tryinto_ok<A_sync_Barrier>()
    into_ok<A_sync_Barrier>()
    send_ok<A_sync_Barrier>()
    sync_ok<A_sync_Barrier>()
    // sync::Condvar
    any_ok<A_sync_Condvar>()
    borrow_ok<A_sync_Condvar>()
    from_ok<A_sync_Condvar>()
    tryfrom_ok<A_sync_Condvar>()
    tryinto_ok<A_sync_Condvar>()
    into_ok<A_sync_Condvar>()
    send_ok<A_sync_Condvar>()
    sync_ok<A_sync_Condvar>()
    // sync::Mutex
    any_ok<A_sync_Mutex>()
    borrow_ok<A_sync_Mutex>()
    from_ok<A_sync_Mutex>()
    tryfrom_ok<A_sync_Mutex>()
    tryinto_ok<A_sync_Mutex>()
    into_ok<A_sync_Mutex>()
    send_ok<A_sync_Mutex>()
    sync_ok<A_sync_Mutex>()
    // sync::MutexGuard
    borrow_ok<A_sync_MutexGuard>()
    from_ok<A_sync_MutexGuard>()
    tryfrom_ok<A_sync_MutexGuard>()
    tryinto_ok<A_sync_MutexGuard>()
    into_ok<A_sync_MutexGuard>()
    sync_ok<A_sync_MutexGuard>()
    string_ok<A_sync_MutexGuard>()
    // sync::Once
    any_ok<A_sync_Once>()
    borrow_ok<A_sync_Once>()
    from_ok<A_sync_Once>()
    tryfrom_ok<A_sync_Once>()
    tryinto_ok<A_sync_Once>()
    into_ok<A_sync_Once>()
    send_ok<A_sync_Once>()
    sync_ok<A_sync_Once>()
    // sync::OnceLock
    any_ok<A_sync_OnceLock>()
    borrow_ok<A_sync_OnceLock>()
    from_ok<A_sync_OnceLock>()
    tryfrom_ok<A_sync_OnceLock>()
    tryinto_ok<A_sync_OnceLock>()
    into_ok<A_sync_OnceLock>()
    send_ok<A_sync_OnceLock>()
    sync_ok<A_sync_OnceLock>()
    owned_ok<A_sync_OnceLock>()
    // sync::RwLock
    any_ok<A_sync_RwLock>()
    borrow_ok<A_sync_RwLock>()
    from_ok<A_sync_RwLock>()
    tryfrom_ok<A_sync_RwLock>()
    tryinto_ok<A_sync_RwLock>()
    into_ok<A_sync_RwLock>()
    send_ok<A_sync_RwLock>()
    sync_ok<A_sync_RwLock>()
    // sync::RwLockReadGuard
    borrow_ok<A_sync_RwLockReadGuard>()
    from_ok<A_sync_RwLockReadGuard>()
    tryfrom_ok<A_sync_RwLockReadGuard>()
    tryinto_ok<A_sync_RwLockReadGuard>()
    into_ok<A_sync_RwLockReadGuard>()
    sync_ok<A_sync_RwLockReadGuard>()
    string_ok<A_sync_RwLockReadGuard>()
    // sync::RwLockWriteGuard
    borrow_ok<A_sync_RwLockWriteGuard>()
    from_ok<A_sync_RwLockWriteGuard>()
    tryfrom_ok<A_sync_RwLockWriteGuard>()
    tryinto_ok<A_sync_RwLockWriteGuard>()
    into_ok<A_sync_RwLockWriteGuard>()
    sync_ok<A_sync_RwLockWriteGuard>()
    string_ok<A_sync_RwLockWriteGuard>()
    // sync::Weak
    any_ok<A_sync_Weak>()
    borrow_ok<A_sync_Weak>()
    from_ok<A_sync_Weak>()
    tryfrom_ok<A_sync_Weak>()
    tryinto_ok<A_sync_Weak>()
    into_ok<A_sync_Weak>()
    send_ok<A_sync_Weak>()
    sync_ok<A_sync_Weak>()
    owned_ok<A_sync_Weak>()
    // sync::atomic::Ordering
    any_ok<A_sync_atomic_Ordering>()
    borrow_ok<A_sync_atomic_Ordering>()
    from_ok<A_sync_atomic_Ordering>()
    tryfrom_ok<A_sync_atomic_Ordering>()
    tryinto_ok<A_sync_atomic_Ordering>()
    into_ok<A_sync_atomic_Ordering>()
    send_ok<A_sync_atomic_Ordering>()
    sync_ok<A_sync_atomic_Ordering>()
    // sync::mpsc::Receiver
    any_ok<A_sync_mpsc_Receiver>()
    borrow_ok<A_sync_mpsc_Receiver>()
    from_ok<A_sync_mpsc_Receiver>()
    tryfrom_ok<A_sync_mpsc_Receiver>()
    tryinto_ok<A_sync_mpsc_Receiver>()
    into_ok<A_sync_mpsc_Receiver>()
    send_ok<A_sync_mpsc_Receiver>()
    // sync::mpsc::Sender
    any_ok<A_sync_mpsc_Sender>()
    borrow_ok<A_sync_mpsc_Sender>()
    from_ok<A_sync_mpsc_Sender>()
    tryfrom_ok<A_sync_mpsc_Sender>()
    tryinto_ok<A_sync_mpsc_Sender>()
    into_ok<A_sync_mpsc_Sender>()
    send_ok<A_sync_mpsc_Sender>()
    sync_ok<A_sync_mpsc_Sender>()
    owned_ok<A_sync_mpsc_Sender>()
    // sync::mpsc::SyncSender
    any_ok<A_sync_mpsc_SyncSender>()
    borrow_ok<A_sync_mpsc_SyncSender>()
    from_ok<A_sync_mpsc_SyncSender>()
    tryfrom_ok<A_sync_mpsc_SyncSender>()
    tryinto_ok<A_sync_mpsc_SyncSender>()
    into_ok<A_sync_mpsc_SyncSender>()
    send_ok<A_sync_mpsc_SyncSender>()
    sync_ok<A_sync_mpsc_SyncSender>()
    owned_ok<A_sync_mpsc_SyncSender>()
    // gap sync::MutexGuard Any: region-borrowing field makes Static fail even at region static
    // gap sync::MutexGuard Send: negative impl (not Transferable) matches Rust; evidenced by fail test
    // gap sync::RwLockReadGuard Any: region-borrowing field makes Static fail even at region static
    // gap sync::RwLockReadGuard Send: negative impl (not Transferable) matches Rust; evidenced by fail test
    // gap sync::RwLockWriteGuard Any: region-borrowing field makes Static fail even at region static
    // gap sync::RwLockWriteGuard Send: negative impl (not Transferable) matches Rust; evidenced by fail test
    // gap sync::atomic::Ordering ToOwned: no Clone implementation
    // gap sync::mpsc::Receiver Sync: negative impl (not Shareable) matches Rust; evidenced by fail test
    0
}
