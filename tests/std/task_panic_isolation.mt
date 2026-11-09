import alloc.arc
import alloc.arc.Arc
import core.future.{Context, Future, Poll}
import std.task

type Panics {
    drops: Arc<core.sync.atomic.AtomicUsize>
    drop { let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}
extend Panics implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> {
        panic("task poll panic")
    }
}

type DropPanics { drop { panic("task destructor panic") } }
extend DropPanics implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> { Poll.Ready(5) }
}

type Ready {}
extend Ready implements Future {
    type Output = i32
    fn poll(receiver take self: pinned mut Self, mut cx: Context): Poll<i32> { Poll.Ready(42) }
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let ex = task.executor()
    let bad = ex.spawn(Panics(drops.retain()))
    let bad_drop = ex.spawn(DropPanics())
    let good = ex.spawn(Ready())
    ex.run()

    match take capture bad.join() {
        failure(task.JoinError.Panicked(code)) => { if code != 101 { return 1 } },
        _ => { return 2 }
    }
    match take capture bad_drop.join() {
        failure(task.JoinError.Panicked(code)) => { if code != 101 { return 3 } },
        _ => { return 4 }
    }
    match take capture good.join() {
        success(value) => { if value != 42 { return 5 } },
        failure(error) => { return 6 }
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 7 }
    0
}
