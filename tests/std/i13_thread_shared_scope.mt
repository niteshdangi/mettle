import std.thread
import std.panic.{catch_panic, CatchResult}
import core.sync.atomic.{AtomicBool, AtomicUsize, Ordering}

type Tracked<region r> {
    drops: read AtomicUsize from r
    drop { let _previous = self.drops.fetch_add(1usize, Ordering.SeqCst) }
}

fn main(): i32 {
    let drops = AtomicUsize.new(0usize)
    let release = AtomicBool.new(false)
    let registered = AtomicBool.new(false)
    let observed = AtomicBool.new(false)
    let nested = AtomicUsize.new(0usize)
    thread.scope(fn(read scope: thread.Scope): Unit {
        let release_ref = read release
        let registered_ref = read registered
        let observed_ref = read observed
        let nested_ref = read nested
        let target = scope.spawn(fn(): i32 {
            let _tracked = Tracked(read drops)
            while !release.load(Ordering.Acquire) { thread.yield_now() }
            panic("observed transferred child")
        })
        let joiner = scope.spawn(take fn(): Unit {
            let child = scope.spawn(fn(): Unit {
                let grandchild = scope.spawn(fn(): Unit {
                    let _old = nested_ref.fetch_add(1usize, Ordering.SeqCst)
                })
            })
            registered_ref.store(true, Ordering.Release)
            release_ref.store(true, Ordering.Release)
            match take capture target.join() {
                success(_) => { panic("expected child panic") },
                failure(error) => {
                    if error.code != 101 { panic("wrong panic code") }
                    observed_ref.store(true, Ordering.Release)
                }
            }
        })
        while !registered.load(Ordering.Acquire) { thread.yield_now() }
    })
    if !observed.load(Ordering.Acquire) ||
       nested.load(Ordering.SeqCst) != 1usize ||
       drops.load(Ordering.SeqCst) != 1usize { return 1 }

    let hits = AtomicUsize.new(0usize)
    let result = catch_panic(fn(): Unit {
        thread.scope(fn(read scope: thread.Scope): Unit {
            let child = scope.spawn(fn(): Unit {
                let grandchild = scope.spawn(fn(): Unit {
                    let _old = hits.fetch_add(1usize, Ordering.SeqCst)
                    panic("unobserved nested child")
                })
            })
        })
    })
    match take result {
        CatchResult.Returned(_) => { return 2 },
        CatchResult.Panicked(_) => {}
    }
    if hits.load(Ordering.SeqCst) != 1usize { return 3 }

    let result = thread.scope(fn(read scope: thread.Scope): i32 {
        let child = scope.spawn(fn(): core.cell.Cell<i32> { core.cell.Cell.new(42) })
        let observer = scope.spawn(fn(): Unit {
            while !child.is_finished() { thread.yield_now() }
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
