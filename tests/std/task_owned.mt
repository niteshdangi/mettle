import core::future::{Context, Future, Poll, Waker};
import std::task;
import std::thread;

// These raw pointers remain valid on the executor thread until all tasks and
// saved wakers have been dropped. The test never transfers the task itself.
type Probe {
    drops: ptr<mut i32>
    saved: ptr<mut Waker?>
    polls: i32
    complete: bool
    drop { unsafe { *self.drops += 1 } }
}
unsafe impl Probe implements Transferable {}
impl Probe implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        me.polls += 1
        if me.polls == 1 {
            unsafe { *me.saved = present(cx.waker().clone()) }
            if me.complete {
                cx.waker().wake_by_ref()
                cx.waker().wake_by_ref()
            }
            Poll::Pending
        } else {
            Poll::Ready(42)
        }
    }
}

// This future never becomes ready and therefore needs no wake.
type Dormant {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
unsafe impl Dormant implements Transferable {}
impl Dormant implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        Poll::Pending
    }
}

fn hammer(waker: take Waker): Unit {
    var i = 0
    while i < 1000 {
        waker.wake_by_ref()
        i += 1
    }
}

fn main(): i32 {
    var drops = 0
    var saved: Waker? = none
    let ex = task::executor()

    // join drives the executor and coalesces repeated wakeups.
    let ready = ex.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, true))
    let result = capture ready.join()
    match take result {
        success(value) => { if value != 42 { return 1 } },
        failure(error) => { return 2 }
    }
    if drops != 1 || ex.pending() != 0usize { return 3 }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 4 }
    }
    if ex.run_until_stalled() != 0usize { return 5 }
    saved = none

    // An abort after Pending drops the future once; retained wakes are inert.
    let pending = ex.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, false))
    if ex.run_until_stalled() != 1usize || drops != 1 { return 6 }
    pending.abort()
    pending.abort()
    if drops != 2 || ex.pending() != 0usize { return 7 }
    match take capture pending.join() {
        failure(task::JoinError::Cancelled) => {},
        _ => { return 8 }
    }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 9 }
    }
    if ex.run_until_stalled() != 0usize { return 10 }
    saved = none

    // Dropping a handle cancels even before its first poll.
    {
        let abandoned = ex.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, false))
    }
    if drops != 3 || ex.pending() != 0usize { return 11 }

    // A forgotten pending handle cannot remove the executor's registration.
    {
        let other = task::executor()
        let forgotten = other.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, false))
        core::mem::forget(take forgotten)
        if other.run_until_stalled() != 1usize || drops != 3 { return 12 }
    }
    if drops != 4 { return 13 }
    match mut saved {
        present(waker) => { waker.wake_by_ref() },
        none => { return 14 }
    }
    saved = none

    // A task which retains no waker is still owned by the executor.
    {
        let other = task::executor()
        let forgotten = other.spawn(Dormant(core::ptr::from_mut(drops)))
        core::mem::forget(take forgotten)
        if other.run_until_stalled() != 1usize || drops != 4 { return 15 }
    }
    if drops != 5 { return 16 }

    // Foreign wake calls can race cancellation, but cannot revive the task.
    let racing = ex.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, false))
    let _polls = ex.run_until_stalled()
    let sender = saved.take_value().unwrap()
    let worker = thread::spawn(take fn(): Unit { hammer(sender) })
    racing.abort()
    let outcome = capture worker.join()
    match take outcome { success(value) => {}, failure(error) => { return 17 } }
    let _stale = ex.run_until_stalled()
    if drops != 6 || ex.pending() != 0usize || ex.run_until_stalled() != 0usize { return 18 }

    {
        let abandoned = ex.spawn(Probe(core::ptr::from_mut(drops), core::ptr::from_mut(saved), 0, false))
        if ex.run_until_stalled() != 1usize { return 19 }
    }
    if drops != 7 || ex.pending() != 0usize { return 20 }
    match mut saved {
        present(waker) => { waker.wake_by_ref() },
        none => { return 21 }
    }
    if ex.run_until_stalled() != 0usize { return 22 }
    saved = none
    0
}
