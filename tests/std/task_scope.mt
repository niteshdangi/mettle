import alloc.arc
import alloc.rc
import alloc.rc.Rc
import core.future.{Context, Future, Poll, Waker}
import std.task
import std.thread

type Child<region r> {
    value: read i32 from r
    drops: read core.sync.atomic.AtomicUsize from r
    saved: ptr<mut Waker?>
    pending: bool
    drop { let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}
extend<region r> Child<region r> implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.pending {
            unsafe { *me.saved = present(cx.waker().clone()) }
            Poll.Pending
        } else {
            Poll.Ready(*me.value)
        }
    }
}

type Parent<region r> {
    value: read i32 from r
    drops: read core.sync.atomic.AtomicUsize from r
    saved: ptr<mut Waker?>
}
extend<region r> Parent<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        let value = me.value
        let drops = me.drops
        let saved = me.saved
        task.scope(fn(read s: task.Scope): Unit {
            let child = s.spawn(Child(value, drops, saved, true))
            core.mem.forget(take child)
        })
        Poll.Pending
    }
}

type SelfCancel<region r> {
    holder: Rc<core.cell.RefCell<task.JoinHandle<Unit>?>>
    drops: read core.sync.atomic.AtomicUsize from r
    drop { let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}
extend<region r> SelfCancel<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        {
            var guard = me.holder.get().borrow_mut()
            let handle = guard.get_mut().take_value()
        }
        Poll.Pending
    }
}

fn main(): i32 {
    let value = 42
    let drops = core.sync.atomic.AtomicUsize.new(0usize)
    var saved: Waker? = none
    let saved_ptr = core.ptr.from_mut(saved)
    let result = task.scope(fn(read s: task.Scope): i32 {
        let child = s.spawn(Child(read value, read drops, saved_ptr, false))
        match take capture child.join() {
            success(v) => v,
            failure(error) => -1
        }
    })
    if result != 42 || drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 1 }

    task.scope(fn(read s: task.Scope): Unit {
        let forgotten = s.spawn(Child(read value, read drops, saved_ptr, true))
        core.mem.forget(take forgotten)
    })
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 2usize { return 2 }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 3 }
    }
    saved = none

    // Unwinding the parent still cancels a forgotten borrowing child.
    let count = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let probe = count.retain()
    let worker = thread.spawn(take fn(): Unit {
        let borrowed_local = 8
        var no_waker: Waker? = none
        let ptr = core.ptr.from_mut(no_waker)
        task.scope(fn(read s: task.Scope): Unit {
            let forgotten = s.spawn(Child(read borrowed_local, probe.get(), ptr, true))
            core.mem.forget(take forgotten)
            panic("scope parent panic")
        })
    })
    match take capture worker.join() {
        failure(error) => { if error.code != 101 { return 4 } },
        success(value) => { return 5 }
    }
    if count.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 6 }

    // Forgetting a parent after Pending leaves no child able to use its
    // expired external borrow, even if a retained wake arrives later.
    {
        let short = 11
        var parent = Parent(read short, read drops, saved_ptr)
        {
            var pin_ = core.pin.Pin.new(mut parent)
            let waker = core.future.noop_waker()
            var cx = Context.from_waker(read waker)
            match take pin_.as_mut().poll(mut cx) {
                Poll.Pending => {},
                Poll.Ready(unit) => { return 7 }
            }
        }
        core.mem.forget(take parent)
    }
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 3usize { return 8 }
    match mut saved {
        present(waker) => { waker.wake_by_ref(); waker.wake_by_ref() },
        none => { return 9 }
    }
    saved = none

    // Dropping the current task's handle from its own poll defers destruction
    // until the poll returns instead of recursively locking its future.
    let cell: core.cell.RefCell<task.JoinHandle<Unit>?> = core.cell.RefCell.new(none)
    let holder = rc.new(cell)
    task.scope(fn(read s: task.Scope): Unit {
        let child = s.spawn(SelfCancel(holder.retain(), read drops))
        var guard = holder.get().borrow_mut()
        *guard.get_mut() = present(child)
    })
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 4usize { return 10 }
    0
}
