import core.future.{Context, Future, Poll}
import std.panic.CatchResult
import std.task

type Ready {}
extend Ready implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        Poll.Ready(())
    }
}

fn main(): i32 {
    let poll_again = std.panic.catch_panic(take fn(): Unit {
        let anchor = 0
        var scope = task.async_scope(read anchor)
        var pin_ = core.pin.Pin.new(mut scope)
        let waker = core.future.noop_waker()
        var first_cx = Context.from_waker(read waker)
        match take pin_.as_mut().poll(mut first_cx) {
            Poll.Ready(unit) => {},
            Poll.Pending => { panic("empty scope did not complete") }
        }
        var second_cx = Context.from_waker(read waker)
        let _again = pin_.as_mut().poll(mut second_cx)
    })
    match take poll_again {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 1 }
        },
        CatchResult.Returned(value) => { return 2 }
    }

    let spawn_after = std.panic.catch_panic(take fn(): Unit {
        let anchor = 0
        var scope = task.async_scope(read anchor)
        var pin_ = core.pin.Pin.new(mut scope)
        let waker = core.future.noop_waker()
        var cx = Context.from_waker(read waker)
        match take pin_.as_mut().poll(mut cx) {
            Poll.Ready(unit) => {},
            Poll.Pending => { panic("empty scope did not complete") }
        }
        // Safety: the scope stays pinned; spawn mutates it without moving it.
        let me = unsafe { pin_.as_mut().get_unchecked_mut() }
        let _child = me.spawn(Ready())
    })
    match take spawn_after {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 3 }
        },
        CatchResult.Returned(value) => { return 4 }
    }
    0
}
