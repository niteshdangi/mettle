import core.future.{Context, Future, Poll, Waker}
import std.task

type Ready {
    saved: ptr<mut Waker?>
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
// The pointers refer to the executor thread's locals. Every task completes and
// every retained waker is released before these locals leave scope.
unsafe extend Ready implements Transferable {}
extend Ready implements Future {
    type Output = i32
    fn poll(receiver self: take pinned mut Self, cx: mut Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        unsafe { *me.saved = present(cx.waker().clone()) }
        Poll.Ready(42)
    }
}

fn main(): i32 {
    var saved: Waker? = none
    var drops = 0
    {
        let executor = task.executor()
        var i = 0
        while i < 256 {
            let handle = executor.spawn(Ready(core.ptr.from_mut(saved), core.ptr.from_mut(drops)))
            match take capture handle.join() {
                success(value) => { if value != 42 { return 1 } },
                failure(_) => { return 2 }
            }
            // Sweeping releases registry ownership while this stale waker lives.
            if executor.run_until_stalled() != 0usize { return 3 }
            match mut saved { present(waker) => { waker.wake_by_ref() }, none => { return 4 } }
            saved = none
            i += 1
        }
        if executor.pending() != 0usize || drops != 256 { return 5 }
    }
    0
}
