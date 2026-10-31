import core.future.{Future, Poll, Context, noop_waker}

// Locals of a coroutine drop in reverse declaration order whether the body
// completes or its future is dropped while suspended, and a nested block's
// locals drop at the block exit even when the block spans a suspension.

type YieldOnce { yielded: bool }
extend YieldOnce implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded { Poll.Ready(()) } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}
fn suspend(): YieldOnce { YieldOnce(false) }

type Guard {
    log: ptr<mut i32>
    id: i32
    drop { unsafe { *self.log = *self.log * 10 + self.id } }
}

async fn ordered(log: ptr<mut i32>): Unit {
    let first = Guard(log, 1)
    {
        let inner = Guard(log, 2)
        await suspend()
    }
    let third = Guard(log, 3)
    await suspend()
    let fourth = Guard(log, 4)
}

fn poll_times<F: Future>(future: take F, times: i32): Unit {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    var left = times
    while left > 0 {
        var cx = Context.from_waker(read waker)
        let _ = slot.as_mut().poll(mut cx)
        left = left - 1
    }
}

fn run(times: i32): i32 {
    var log = 0
    poll_times(ordered(core.ptr.from_mut(mut log)), times)
    log
}

fn main(): i32 {
    if run(0) != 0 { return 1 }
    if run(1) != 21 { return 2 }
    if run(2) != 231 { return 3 }
    if run(3) != 2431 { return 4 }
    0
}
