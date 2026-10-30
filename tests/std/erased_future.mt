import alloc.future;
import alloc.arc;
import alloc.arc.Arc;
import core.future.{Context, Future, Poll};
import std.task;
import std.thread;

type Stable {
    address: ptr<mut u8>
    drops: ptr<mut i32>
    marker: core.marker.PhantomPinned
    drop { unsafe { *self.drops = *self.drops + 1 } }
}

extend Stable implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        let address = core.ptr.from_mut(*me).cast<u8>()
        if me.address == core.ptr.null_mut<u8>() {
            me.address = address
            cx.waker().wake_by_ref()
            Poll.Pending
        } else {
            if me.address != address { return Poll.Ready(-1) }
            Poll.Ready(42)
        }
    }
}

type Panics {
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop { let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}
extend Panics implements Future {
    type Output = Unit
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<Unit> {
        panic("erased future panic")
    }
}

fn main(): i32 {
    var drops = 0
    let state = Stable(core.ptr.null_mut<u8>(), core.ptr.from_mut(drops), core.marker.PhantomPinned)
    var erased = future.erase(state)
    {
        var handle = core.pin.Pin.new(mut erased)
        let waker = core.future.noop_waker()
        var cx = Context.from_waker(read waker)
        match take handle.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return 1 },
            Poll.Pending => {}
        }
    }
    if task.block_on(erased) != 42 || drops != 1 { return 1 }

    {
        let state = Stable(core.ptr.null_mut<u8>(), core.ptr.from_mut(drops), core.marker.PhantomPinned)
        var slot = core.pin.pin(future.erase(state))
        let waker = core.future.noop_waker()
        var cx = Context.from_waker(read waker)
        match take slot.as_mut().poll(mut cx) {
            Poll.Ready(value) => { return 2 },
            Poll.Pending => {}
        }
        if drops != 1 { return 3 }
    }
    if drops != 2 { return 4 }

    let count = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let other = count.retain()
    let worker = thread.spawn(take fn(): Unit {
        task.block_on(future.erase(Panics(other.retain())))
    })
    let result = capture worker.join()
    match take result {
        success(value) => { return 5 },
        failure(error) => { if error.code != 101 { return 6 } }
    }
    if count.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 7 }
    0
}
