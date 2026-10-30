// expect-exit: 101
// expect-stderr: async future polled after completion
import std::task;
import core::future::{Future, Poll, Context};

type Count { left: i32 }
impl Count implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.left == 0 { Poll::Ready(5) } else {
            me.left = me.left - 1
            cx.waker().wake_by_ref()
            Poll::Pending
        }
    }
}

type Guard { p: ptr<mut i32>; drop { unsafe { *self.p = *self.p + 1 } } }

async fn holds(p: ptr<mut i32>): i32 {
    let g = Guard(p)
    let x = await Count(5)
    let keep = g.p
    x
}
async fn sum(a: i32): i32 {
    let x = await Count(2)
    let y = await task::yield_now()
    a + x
}
async fn record(p: ptr<mut i32>, v: i32) {
    await task::yield_now();
    unsafe { *p = *p * 10 + v }
}

fn main(): i32 {
    if task::block_on(sum(3)) != 8 { return 1 }

    // Executor: two tasks interleave through yield_now.
    var log = 0
    let ex = task::executor()
    ex.spawn(record(core::ptr::from_mut(log), 1))
    ex.spawn(record(core::ptr::from_mut(log), 2))
    if ex.pending() != 2usize { return 2 }
    ex.run()
    if ex.pending() != 0usize || log != 12 { return 3 }

    // Dropping an unfinished future drops live state exactly once.
    var dropped = 0
    {
        var fut = holds(core::ptr::from_mut(dropped))
        let waker = core::future::noop_waker()
        var cx = Context::from_waker(read waker)
        var pinned = core::pin::pin(fut)
        match take pinned.as_mut().poll(mut cx) {
            Poll::Pending => {},
            Poll::Ready(v) => { return 4 }
        }
        if dropped != 0 { return 5 }
    }
    if dropped != 1 { return 6 }

    // Polling a completed async future is a defined panic.
    let done = sum(1)
    let waker = core::future::noop_waker()
    var pinned = core::pin::pin(done)
    var finished = false
    while !finished {
        var cx = Context::from_waker(read waker)
        match take pinned.as_mut().poll(mut cx) {
            Poll::Ready(v) => { finished = true },
            Poll::Pending => {}
        }
    }
    var cx2 = Context::from_waker(read waker)
    let again = pinned.as_mut().poll(mut cx2)
    7
}
