// expect-exit: 0
// profiles: debug release
// Blanket and auto-property evidence for thread, task and time types. Each call instantiates the
// blanket trait row for a hosted std type. Pairs the compiler cannot satisfy are
// listed as gaps at the end of main; negative impls are evidenced in tests/source/fail.
fn any_ok<T: unsized + core.any.Any>(): Unit {}
fn borrow_ok<T: unsized + core.borrow.Borrow<T>>(): Unit {}
fn owned_ok<T: core.borrow.ToOwned>(): Unit {}
fn from_ok<T: core.convert.From<T>>(): Unit {}
fn into_ok<T: core.convert.Into<T>>(): Unit {}
fn string_ok<T: alloc.string.ToString>(): Unit {}
fn send_ok<T: unsized + Transferable>(): Unit {}
fn sync_ok<T: unsized + Shareable>(): Unit {}
alias A_task_Context = core.future.Context<region static>
alias A_task_Poll = core.future.Poll<i32>
alias A_task_Waker = core.future.Waker
alias A_thread_JoinHandle = std.thread.JoinHandle<i32>
alias A_thread_Scope = std.thread.Scope<region static>
alias A_thread_ScopedJoinHandle = std.thread.ScopedJoinHandle<i32>
alias A_thread_Thread = std.thread.Thread
alias A_time_Duration = std.time.Duration
alias A_time_Instant = std.time.Instant
alias A_time_SystemTime = std.time.SystemTime
fn main(): i32 {
    // task::Context
    borrow_ok<A_task_Context>()
    from_ok<A_task_Context>()
    into_ok<A_task_Context>()
    send_ok<A_task_Context>()
    sync_ok<A_task_Context>()
    // task::Poll
    any_ok<A_task_Poll>()
    borrow_ok<A_task_Poll>()
    from_ok<A_task_Poll>()
    into_ok<A_task_Poll>()
    send_ok<A_task_Poll>()
    sync_ok<A_task_Poll>()
    // task::Waker
    any_ok<A_task_Waker>()
    borrow_ok<A_task_Waker>()
    from_ok<A_task_Waker>()
    into_ok<A_task_Waker>()
    send_ok<A_task_Waker>()
    sync_ok<A_task_Waker>()
    // thread::JoinHandle
    any_ok<A_thread_JoinHandle>()
    borrow_ok<A_thread_JoinHandle>()
    from_ok<A_thread_JoinHandle>()
    into_ok<A_thread_JoinHandle>()
    send_ok<A_thread_JoinHandle>()
    sync_ok<A_thread_JoinHandle>()
    // thread::Scope
    any_ok<A_thread_Scope>()
    borrow_ok<A_thread_Scope>()
    from_ok<A_thread_Scope>()
    into_ok<A_thread_Scope>()
    // thread::ScopedJoinHandle
    any_ok<A_thread_ScopedJoinHandle>()
    borrow_ok<A_thread_ScopedJoinHandle>()
    from_ok<A_thread_ScopedJoinHandle>()
    into_ok<A_thread_ScopedJoinHandle>()
    // thread::Thread
    any_ok<A_thread_Thread>()
    borrow_ok<A_thread_Thread>()
    from_ok<A_thread_Thread>()
    into_ok<A_thread_Thread>()
    send_ok<A_thread_Thread>()
    sync_ok<A_thread_Thread>()
    owned_ok<A_thread_Thread>()
    // time::Duration
    any_ok<A_time_Duration>()
    borrow_ok<A_time_Duration>()
    from_ok<A_time_Duration>()
    into_ok<A_time_Duration>()
    send_ok<A_time_Duration>()
    sync_ok<A_time_Duration>()
    // time::Instant
    any_ok<A_time_Instant>()
    borrow_ok<A_time_Instant>()
    from_ok<A_time_Instant>()
    into_ok<A_time_Instant>()
    send_ok<A_time_Instant>()
    sync_ok<A_time_Instant>()
    // time::SystemTime
    any_ok<A_time_SystemTime>()
    borrow_ok<A_time_SystemTime>()
    from_ok<A_time_SystemTime>()
    into_ok<A_time_SystemTime>()
    send_ok<A_time_SystemTime>()
    sync_ok<A_time_SystemTime>()
    // gap task::Context Any: region-borrowing field makes Static fail even at region static
    // gap task::Poll ToOwned: no Clone implementation
    // gap task::Waker ToOwned: no Clone implementation
    // gap thread::Scope Send: deliberately not Transferable (library thread.mt); Rust auto-derives Send
    // gap thread::Scope Sync: deliberately not Shareable (library thread.mt); Rust auto-derives Sync
    // gap thread::ScopedJoinHandle Send: explicit not Transferable (library thread.mt:407); Rust auto-derives Send
    // gap thread::ScopedJoinHandle Sync: explicit not Shareable (library thread.mt:407); Rust auto-derives Sync
    // gap time::Duration ToOwned: no Clone implementation
    // gap time::Instant ToOwned: no Clone implementation
    // gap time::SystemTime ToOwned: no Clone implementation
    0
}
