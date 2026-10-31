import alloc.future
import core.future.{Context, Future, Poll, noop_waker}
import std.task

type YieldOnce {
    value: i32
    yielded: bool
    drops: ptr<mut i32>
    drop { unsafe { *self.drops = *self.drops + 1 } }
}

extend YieldOnce implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded {
            Poll.Ready(me.value)
        } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

fn poll_erased(
    future: mut any Future<Output = i32>, cx: mut Context
): bool {
    var handle = unsafe { core.pin.Pin.new_unchecked(mut future) }
    match take handle.poll(mut cx) {
        Poll.Ready(_) => true,
        Poll.Pending => false
    }
}

fn main(): i32 {
    var drops = 0
    var stored = future.erase(YieldOnce(
        42, false, core.ptr.from_mut(mut drops)
    ))
    {
        let erased: mut any Future<Output = i32> = mut stored
        let waker = noop_waker()
        var cx = Context.from_waker(read waker)
        if poll_erased(erased, mut cx) { return 1 }
    }
    if task.block_on(stored) != 42 { return 2 }
    if drops != 1 { return 3 }
    0
}
