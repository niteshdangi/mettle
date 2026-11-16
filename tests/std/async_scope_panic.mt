import alloc.arc
import core.future.{Context, Future, Poll}
import std.panic.CatchResult
import std.task

// Raw cleanup copies become sole owners when their originals are forgotten.

type Panics {}
extend Panics implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        panic("async scope child panic")
    }
}

type PendingDrop<region r> {
    drops: read core.sync.atomic.AtomicUsize from r
    drop {
        let _old = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}
extend<region r> PendingDrop<region r> implements Future {
    type Output = Unit
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<Unit> {
        Poll.Pending
    }
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let count = drops.retain()
    let retained = drops.retain()
    let caught = std.panic.catch_panic(take fn(): Unit {
        let counter = retained.get()
        var scope = task.async_scope(counter)
        let panics = scope.spawn(Panics())
        let reclaimed_panics = unsafe { core.ptr.`read`(core.ptr.from_ref(panics)) }
        core.mem.forget(take panics)
        let sibling = scope.spawn(PendingDrop(counter))
        let reclaimed_sibling = unsafe { core.ptr.`read`(core.ptr.from_ref(sibling)) }
        core.mem.forget(take sibling)
        task.block_on(take scope)
    })
    match take caught {
        CatchResult.Panicked(info) => {
            if info.code() != 101 { return 1 }
        },
        CatchResult.Returned(value) => { return 2 }
    }
    if count.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize {
        return 3
    }
    0
}
