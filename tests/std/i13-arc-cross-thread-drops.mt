// expect-exit: 0
// Evidence for Shared and Weak operations across threads: strong and weak counts
// while workers hold clones, the payload dropping exactly once on whichever
// thread releases the last owner, and unique access once the workers join.
import std.thread
import alloc.arc
import core.clone.Clone

type Tracked {
    drops: arc.Shared<core.sync.atomic.AtomicUsize>
    value: i32
    drop {
        let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst)
    }
}

fn discard<T>(take value: T): Unit {}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let owner = arc.new(Tracked(drops.retain(), 6))
    let observer = owner.downgrade()
    // workers wait on this gate so main can observe counts while they hold clones
    let gate = arc.new(core.sync.atomic.AtomicBool.new(false))

    // each worker keeps its own strong clone and reports what it observed
    var handles = alloc.vec.new<thread.JoinHandle<i32>>()
    var spawned = 0
    while spawned < 3 {
        let worker = owner.retain()
        let weak_view = observer.clone()
        let worker_gate = gate.retain()
        handles.push(thread.spawn(take fn(): i32 {
            while !worker_gate.get().load(core.sync.atomic.Ordering.Acquire) {
                thread.yield_now()
            }
            var bad = 0
            if worker.strong_count() < 1usize { bad = bad + 1 }
            if worker.get().value != 6 { bad = bad + 2 }
            match weak_view.upgrade() {
                present(strong) => { if strong.get().value != 6 { bad = bad + 4 } },
                none => { bad = bad + 8 }
            }
            if !worker.ptr_eq(worker.retain()) { bad = bad + 16 }
            bad
        }))
        spawned += 1
    }
    if owner.strong_count() != 4usize || observer.weak_count() != 4usize { return 1 }

    // the main owner gives up its handle first; the workers hold the payload
    discard(take owner)
    if observer.strong_count() != 3usize { return 2 }
    gate.get().store(true, core.sync.atomic.Ordering.Release)
    var collected = 0
    while true {
        let next = handles.pop()
        match take next {
            present(handle) => {
                let joined = capture handle.join()
                match take joined {
                    success(bad) => { collected += bad },
                    failure(_) => { return 3 }
                }
            },
            none => { break }
        }
    }
    if collected != 0 { return 4 }

    // the last worker to finish drops the payload exactly once and the weak
    // observer sees the dead payload
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 5 }
    if observer.strong_count() != 0usize || observer.upgrade().is_present() { return 6 }

    // a fresh allocation whose workers finish before the main owner is
    // unique again and yields its payload through try_unwrap
    let sole = arc.new(Tracked(drops.retain(), 8))
    let helper = sole.retain()
    let finished = thread.spawn(take fn(): i32 {
        if helper.strong_count() < 1usize { 1 } else { 0 }
    })
    let finished_result = capture finished.join()
    match take finished_result {
        success(code) => { if code != 0 { return 7 } },
        failure(_) => { return 8 }
    }
    if sole.strong_count() != 1usize { return 9 }
    let unwrapped = capture sole.try_unwrap()
    match take unwrapped {
        success(value) => { if value.value != 8 { return 10 } },
        failure(_) => { return 11 }
    }
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize { return 12 }
    0
}
