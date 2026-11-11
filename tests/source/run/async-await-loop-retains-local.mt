module source_helpers;
import core.future.{Future, Poll, Context, noop_waker}

type YieldOnce { yielded: bool }
extend YieldOnce implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        let me = unsafe { self.get_unchecked_mut() }
        if me.yielded {
            Poll.Ready(1)
        } else {
            me.yielded = true
            cx.waker().wake_by_ref()
            Poll.Pending
        }
    }
}

type Guard {
    counter: ptr<mut i32>
    drop { unsafe { *self.counter = *self.counter + 10 } }
}

async fn count(counter: ptr<mut i32>): i32 {
    let guard = Guard(counter)
    var index = 0
    while index < 2 {
        let value = await YieldOnce(false)
        unsafe { *guard.counter = *guard.counter + value }
        index = index + 1
    }
    index
}

fn drive<F: Future<Output = i32>>(take future: F): i32 {
    source_helpers.drive!(future)
}

fn abandon<F: Future<Output = i32>>(take future: F): Unit {
    let waker = noop_waker()
    var slot = core.pin.pin(future)
    var cx = Context.from_waker(read waker)
    match take slot.as_mut().poll(mut cx) {
        Poll.Ready(value) => { return },
        Poll.Pending => {}
    }
}

fn main(): i32 {
    var counter = 0
    let result = drive(count(core.ptr.from_mut(counter)))
    if result != 2 || counter != 12 { return 1 }
    var cancelled = 0
    abandon(count(core.ptr.from_mut(cancelled)))
    if cancelled == 10 { 0 } else { 2 }
}
