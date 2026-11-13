import alloc.arc
import std.thread

fn collective(): i32 {
    let owner = arc.new(37)
    let slot = core.cell.Cell.new(present(owner.retain()))
    let phase = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let worker_phase = phase.retain()
    let worker = thread.spawn(take fn(): i32 {
        let sibling = slot.replace(none).or_panic()
        worker_phase.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
        while worker_phase.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize {
            thread.yield_now()
        }
        match take sibling.into_inner() {
            present(value) => if value == 37 { 1 } else { 100 },
            none => 0
        }
    })
    while phase.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { thread.yield_now() }
    phase.get().store(2usize, core.sync.atomic.Ordering.SeqCst)
    let extracted = match take owner.into_inner() {
        present(value) => if value == 37 { 1 } else { 100 },
        none => 0
    }
    match capture worker.join() {
        success(remote) => if extracted + remote == 1 { 0 } else { 1 },
        failure(_) => 2
    }
}

fn unique(): i32 {
    var owner = arc.new(41)
    let slot = core.cell.Cell.new(present(owner.retain()))
    let phase = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let worker_phase = phase.retain()
    let exclusive = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let worker_exclusive = exclusive.retain()
    let worker = thread.spawn(take fn(): i32 {
        let sibling = slot.replace(none).or_panic()
        while worker_phase.get().load(core.sync.atomic.Ordering.SeqCst) == 0usize {
            thread.yield_now()
        }
        let observer = sibling.downgrade()
        core.mem.drop(take sibling)
        var attempt = 0usize
        while attempt < 64usize {
            match take observer.upgrade() {
                present(strong) => {
                    if worker_exclusive.get().load(core.sync.atomic.Ordering.SeqCst) != 0usize {
                        return 1
                    }
                    let _ = strong.strong_count()
                },
                none => { return 2 }
            }
            attempt += 1usize
        }
        0
    })
    phase.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
    var attempt = 0usize
    while attempt < 64usize {
        match take owner.get_mut() {
            present(value) => {
                exclusive.get().store(1usize, core.sync.atomic.Ordering.SeqCst)
                thread.yield_now()
                *value += 1
                exclusive.get().store(0usize, core.sync.atomic.Ordering.SeqCst)
            },
            none => {}
        }
        attempt += 1usize
    }
    match capture worker.join() {
        success(code) => code,
        failure(_) => 3
    }
}

fn main(): i32 {
    var round = 0usize
    while round < 128usize {
        if collective() != 0 { return 1 }
        if unique() != 0 { return 2 }
        round += 1usize
    }
    0
}
