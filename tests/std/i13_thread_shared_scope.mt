import std.thread
import std.panic.{catch_panic, CatchResult}

type Tracked<region r> {
    drops: read core.sync.atomic.AtomicUsize from r
    drop { let _previous = self.drops.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}

fn main(): i32 {
    let drops = core.sync.atomic.AtomicUsize.new(0usize)
    let release = core.sync.atomic.AtomicBool.new(false)
    let registered = core.sync.atomic.AtomicBool.new(false)
    let observed = core.sync.atomic.AtomicBool.new(false)
    let nested = core.sync.atomic.AtomicUsize.new(0usize)
    thread.scope(fn(read scope: thread.Scope): Unit {
        let release_ref = read release
        let registered_ref = read registered
        let observed_ref = read observed
        let nested_ref = read nested
        let target = scope.spawn(fn(): i32 {
            let _tracked = Tracked(read drops)
            while !release.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
            panic("observed transferred child")
        })
        let joiner = scope.spawn(take fn(): Unit {
            let child = scope.spawn(take fn(): Unit {
                let grandchild = scope.spawn(take fn(): Unit {
                    let _old = nested_ref.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
                })
            })
            registered_ref.store(true, core.sync.atomic.Ordering.Release)
            release_ref.store(true, core.sync.atomic.Ordering.Release)
            match take capture target.join() {
                success(_) => { panic("expected child panic") },
                failure(error) => {
                    if error.code != 101 { panic("wrong panic code") }
                    observed_ref.store(true, core.sync.atomic.Ordering.Release)
                }
            }
        })
        while !registered.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
    })
    if !observed.load(core.sync.atomic.Ordering.Acquire) ||
       nested.load(core.sync.atomic.Ordering.SeqCst) != 1usize ||
       drops.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 1 }

    let hits = core.sync.atomic.AtomicUsize.new(0usize)
    let result = catch_panic(fn(): Unit {
        thread.scope(fn(read scope: thread.Scope): Unit {
            let child = scope.spawn(fn(): Unit {
                let grandchild = scope.spawn(fn(): Unit {
                    let _old = hits.fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
                    panic("unobserved nested child")
                })
            })
        })
    })
    match take result {
        CatchResult.Returned(_) => { return 2 },
        CatchResult.Panicked(_) => {}
    }
    if hits.load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 3 }

    let child_done = core.sync.atomic.AtomicBool.new(false)
    let result = thread.scope(fn(read scope: thread.Scope): i32 {
        let child = scope.spawn(fn(): core.cell.Cell<i32> {
            child_done.store(true, core.sync.atomic.Ordering.Release)
            core.cell.Cell.new(42)
        })
        let observer = scope.spawn(fn(): Unit {
            while !child_done.load(core.sync.atomic.Ordering.Acquire) { thread.yield_now() }
        })
        match take capture observer.join() {
            success(_) => {},
            failure(_) => { return 4 }
        }
        let joiner = scope.spawn(take fn(): i32 {
            match take capture child.join() {
                success(value) => value.get(),
                failure(_) => 0
            }
        })
        match take capture joiner.join() {
            success(value) => value,
            failure(_) => 0
        }
    })
    if result != 42 { return 5 }
    0
}
