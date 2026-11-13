import std.sync.mpsc
import alloc.arc

type Counted {
    drops: arc.Shared<core.sync.atomic.AtomicUsize>
    drop { let _old = self.drops.get().fetch_add(1usize, core.sync.atomic.Ordering.SeqCst) }
}

fn main(): i32 {
    let drops = arc.new(core.sync.atomic.AtomicUsize.new(0usize))
    let unbounded = mpsc.channel<Counted>()
    let sent = capture unbounded.0.send(Counted(drops.retain()))
    if sent.is_failure() { return 1 }
    core.mem.drop(unbounded.1)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 1usize { return 2 }
    let rejected = capture unbounded.0.send(Counted(drops.retain()))
    if rejected.is_success() { return 3 }
    core.mem.drop(rejected)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 2usize { return 4 }

    let bounded = mpsc.sync_channel<Counted>(1usize)
    let sent = capture bounded.0.send(Counted(drops.retain()))
    if sent.is_failure() { return 5 }
    core.mem.drop(bounded.1)
    if drops.get().load(core.sync.atomic.Ordering.SeqCst) != 3usize { return 6 }
    0
}
