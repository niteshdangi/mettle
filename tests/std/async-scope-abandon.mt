import core.clone.Clone
import core.future.{Context, Future, Poll, Waker}
import std.task

type Pending<region r> {
    polls: read core.sync.atomic.AtomicUsize from r
    drops: read core.sync.atomic.AtomicUsize from r
    saved: ptr<mut Waker?>
    drop {
        let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

extend<region r> Pending<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        let _old = me.polls.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
        unsafe { *me.saved = present(cx.waker().clone()) }
        Poll.Pending
    }
}

fn main(): i32 {
    let anchor = 0
    let polls = core.sync.atomic.AtomicUsize.new(0usize)
    let drops = core.sync.atomic.AtomicUsize.new(0usize)
    var saved: Waker? = none

    {
        var scope = task.async_scope(read anchor)
        let child = scope.spawn(Pending(read polls, read drops, core.ptr.from_mut(saved)))
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
    if polls.load(core.sync.atomic.Ordering.SeqCst) != 1usize ||
       drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 2 }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 3 }
    }
    saved = none

    {
        let short = 1
        var parent = task.async_scope(read short)
        let child = parent.spawn(Pending(read polls, read drops, core.ptr.from_mut(saved)))
        core.mem.forget(take child)
        {
            var pin_ = core.pin.Pin.new(mut parent)
            let waker = core.future.noop_waker()
            var cx = Context.from_waker(read waker)
            match take pin_.as_mut().poll(mut cx) {
                Poll.Pending => {},
                Poll.Ready(unit) => { return 4 }
            }
        }
        // A forgotten parent may leak its child state, but no child can run
        // after this poll epoch or through a retained wake notification.
        core.mem.forget(take parent)
    }
    match mut saved {
        present(waker) => { waker.wake_by_ref() },
        none => { return 5 }
    }
    if polls.load(core.sync.atomic.Ordering.SeqCst) != 2usize ||
       drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 6 }
    saved = none
    0
}
