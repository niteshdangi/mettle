import core.future.{Context, Future, Poll}
import std.panic.CatchResult
import std.task

type PanicsOnDrop {
    drop { panic("scope child destructor panic") }
}

extend PanicsOnDrop implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        Poll.Pending
    }
}

type CountedPending<region r> {
    drops: read core.sync.atomic.AtomicUsize from r
    drop {
        let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

extend<region r> CountedPending<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        Poll.Pending
    }
}

fn main(): i32 {
    let drops = core.sync.atomic.AtomicUsize.new(0usize)
    let counter = read drops
    let caught = std.panic.catch_panic(take fn(): Unit {
        {
            var scope = task.async_scope(counter)
            let panicker = scope.spawn(PanicsOnDrop())
            core.mem.forget(take panicker)
            let sibling = scope.spawn(CountedPending(counter))
            core.mem.forget(take sibling)
            {
                var pin_ = core.pin.Pin.new(mut scope)
                let waker = core.future.noop_waker()
                var cx = Context.from_waker(read waker)
                match take pin_.as_mut().poll(mut cx) {
                    Poll.Pending => {},
                    Poll.Ready(unit) => { panic("scope completed with pending children") }
                }
            }
        }
    })
    match take caught {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 1 }
        },
        CatchResult.Returned(value) => { return 2 }
    }
    if drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 3 }
    0
}
