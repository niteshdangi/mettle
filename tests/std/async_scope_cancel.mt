import core.future.{Context, Future, Poll, Waker}
import std.task

type Pending<region r> {
    drops: read core.sync.atomic.AtomicUsize from r
    saved: ptr<mut Waker?>
    drop {
        let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

extend<region r> Pending<region r> implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        unsafe { *me.saved = present(cx.waker().clone()) }
        Poll.Pending
    }
}

fn main(): i32 {
    let anchor = 0
    let drops = core.sync.atomic.AtomicUsize.new(0usize)
    var saved: Waker? = none
    {
        var scope = task.async_scope(read anchor)
        let child = scope.spawn(Pending(read drops, core.ptr.from_mut(saved)))
        core.mem.forget(take child)
        {
            var pin_ = core.pin.Pin.new(mut scope)
            let waker = core.future.noop_waker()
            var cx = Context.from_waker(read waker)
            match take pin_.as_mut().poll(mut cx) {
                Poll.Pending => {},
                Poll.Ready(unit) => { return 1 }
            }
        }
    }
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 2 }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 3 }
    }
    saved = none
    0
}
