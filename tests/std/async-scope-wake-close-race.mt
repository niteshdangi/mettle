import alloc.arc
import alloc.arc.Arc
import core.future.{Context, Future, Poll, Waker}
import std.sync.barrier
import std.task
import std.thread

type ParentWake {
    entered: Arc<barrier.Barrier>
    release: Arc<barrier.Barrier>
}

extend ParentWake implements task.Wake {
    fn wake(me: read Arc<ParentWake>): Unit {
        let _entered = me.get().entered.get().wait()
        let _release = me.get().release.get().wait()
    }
}

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
    let entered = arc.new(barrier.new(2usize))
    let release = arc.new(barrier.new(2usize))
    let parent = arc.new(ParentWake(entered.retain(), release.retain()))
    let parent_waker = task.waker_from_arc(read parent)
    var saved: Waker? = none

    let worker = {
        var scope = task.async_scope(read anchor)
        let child = scope.spawn(Pending(read drops, core.ptr.from_mut(saved)))
        core.mem.forget(take child)
        {
            var pin_ = core.pin.Pin.new(mut scope)
            var cx = Context.from_waker(read parent_waker)
            match take pin_.as_mut().poll(mut cx) {
                Poll.Pending => {},
                Poll.Ready(unit) => { return 1 }
            }
        }
        let child_waker = match take saved {
            present(waker) => waker,
            none => { return 2 }
        }
        let worker = thread.spawn(take fn(): i32 {
            child_waker.wake_by_ref()
            0
        })
        let _arrived = entered.get().wait()
        worker
    }

    // The wake callback has cloned the parent waker and is held outside the
    // scope metadata lock while close drains the child and removes that waker.
    let _released = release.get().wait()
    match take capture worker.join() {
        success(0) => {},
        _ => { return 3 }
    }
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 4 }
    0
}
