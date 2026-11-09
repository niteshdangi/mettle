import core.future.{Context, Future, Poll}
import std.task

type SelfRef<region r> {
    value: i32
    saved: ptr<mut i32>
    completed: read core.sync.atomic.AtomicUsize from r
    moved: read core.sync.atomic.AtomicUsize from r
}

extend<region r> SelfRef<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.saved == core.ptr.null_mut<i32>() {
            me.saved = core.ptr.from_mut(me.value)
            cx.waker().wake_by_ref()
            Poll.Pending
        } else {
            if me.saved == core.ptr.from_mut(me.value) {
                let _old = me.completed.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
            } else {
                let _old = me.moved.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
            }
            Poll.Ready(())
        }
    }
}

fn main(): i32 {
    let completed = core.sync.atomic.AtomicUsize.new(0usize)
    let moved = core.sync.atomic.AtomicUsize.new(0usize)
    let anchor = 0
    var scope = task.async_scope(read anchor)
    var index = 0usize
    while index < 256usize {
        let _child = scope.spawn(SelfRef(
            index as i32,
            core.ptr.null_mut<i32>(),
            read completed,
            read moved
        ))
        index += 1usize
    }

    var pin_ = core.pin.Pin.new(mut scope)
    let waker = core.future.noop_waker()
    var first_cx = Context.from_waker(read waker)
    match take pin_.as_mut().poll(mut first_cx) {
        Poll.Pending => {},
        Poll.Ready(unit) => { return 1 }
    }
    var second_cx = Context.from_waker(read waker)
    match take pin_.as_mut().poll(mut second_cx) {
        Poll.Ready(unit) => {},
        Poll.Pending => { return 2 }
    }
    if completed.load(core.sync.atomic.Ordering.SeqCst) != 256usize ||
       moved.load(core.sync.atomic.Ordering.SeqCst) != 0usize { return 3 }
    0
}
