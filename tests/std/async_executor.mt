// expect-exit: 101
// expect-stderr: async future polled after completion
import std.task
import std.sync.mutex
import alloc.arc
import alloc.arc.Arc
import core.future.{Future, Poll, Context}

type Count { left: i32 }
extend Count implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.left == 0 { Poll.Ready(5) } else {
            me.left = me.left - 1
            cx.waker().wake_by_ref()
            Poll.Pending
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
    let y = await task.yield_now()
    a + x
}
async fn record(log: take Arc<mutex.Mutex<i32>>, v: i32) {
    await task.yield_now();
    let locked = capture log.get().lock()
    var guard = match take locked { success(g) => g, failure(e) => e.into_inner() }
    *guard.get_mut() = *guard.get() * 10 + v
}

fn main(): i32 {
    if task.block_on(sum(3)) != 8 { return 1 }

    // Executor: two tasks interleave through yield_now.
    let log = arc.new(mutex.new(0))
    let ex = task.executor()
    let first = ex.spawn(record(log.retain(), 1))
    let second = ex.spawn(record(log.retain(), 2))
    if ex.pending() != 2usize { return 2 }
    ex.run()
    let first_result = capture first.join()
    let second_result = capture second.join()
    match take first_result { success(v) => {}, failure(e) => { return 3 } }
    match take second_result { success(v) => {}, failure(e) => { return 3 } }
    let locked = capture log.get().lock()
    let value = match take locked { success(g) => *g.get(), failure(e) => -1 }
    if ex.pending() != 0usize || value != 12 { return 3 }

    // Dropping an unfinished future drops live state exactly once.
    var dropped = 0
    {
        var fut = holds(core.ptr.from_mut(dropped))
        let waker = core.future.noop_waker()
        var cx = Context.from_waker(read waker)
        var slot = core.pin.pin(fut)
        match take slot.as_mut().poll(mut cx) {
            Poll.Pending => {},
            Poll.Ready(v) => { return 4 }
        }
        if dropped != 0 { return 5 }
    }
    if dropped != 1 { return 6 }

    // Polling a completed async future is a defined panic.
    let done = sum(1)
    let waker = core.future.noop_waker()
    var slot = core.pin.pin(done)
    var finished = false
    while !finished {
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(v) => { finished = true },
            Poll.Pending => {}
        }
    }
    var cx2 = Context.from_waker(read waker)
    let again = slot.as_mut().poll(mut cx2)
    7
}
