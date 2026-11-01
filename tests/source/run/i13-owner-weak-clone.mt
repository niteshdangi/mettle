import alloc.arc
import alloc.rc
import core.clone.Clone

type Tracked {
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var local_drops = 0
    let local_drop_pointer = core.ptr.from_mut(local_drops)
    let local_empty = rc.new_weak<Tracked>()
    let local_empty_copy = local_empty.clone()
    if local_empty.strong_count() != 0usize ||
        local_empty.weak_count() != 0usize ||
        local_empty_copy.strong_count() != 0usize ||
        local_empty_copy.weak_count() != 0usize ||
        local_empty_copy.upgrade().is_present() {
        return 1
    }
    core.mem.drop(take local_empty)
    core.mem.drop(take local_empty_copy)
    {
        let owner = rc.new(Tracked(local_drop_pointer))
        let observer = owner.downgrade()
        let duplicate = observer.clone()
        if owner.weak_count() != 2usize { return 2 }
        core.mem.drop(take owner)
        if local_drops != 1 || observer.strong_count() != 0usize ||
            observer.weak_count() != 0usize ||
            observer.upgrade().is_present() {
            return 3
        }
        core.mem.drop(take observer)
        if duplicate.weak_count() != 0usize { return 4 }
        core.mem.drop(take duplicate)
    }

    var atomic_drops = 0
    let atomic_drop_pointer = core.ptr.from_mut(atomic_drops)
    let atomic_empty = arc.new_weak<Tracked>()
    let atomic_empty_copy = atomic_empty.clone()
    if atomic_empty.strong_count() != 0usize ||
        atomic_empty.weak_count() != 0usize ||
        atomic_empty_copy.strong_count() != 0usize ||
        atomic_empty_copy.weak_count() != 0usize ||
        atomic_empty_copy.upgrade().is_present() {
        return 5
    }
    core.mem.drop(take atomic_empty)
    core.mem.drop(take atomic_empty_copy)
    {
        let owner = arc.new(Tracked(atomic_drop_pointer))
        let observer = owner.downgrade()
        let duplicate = observer.clone()
        if owner.weak_count() != 2usize { return 6 }
        core.mem.drop(take owner)
        if atomic_drops != 1 || observer.strong_count() != 0usize ||
            observer.weak_count() != 0usize ||
            observer.upgrade().is_present() {
            return 7
        }
        core.mem.drop(take observer)
        if duplicate.weak_count() != 0usize { return 8 }
        core.mem.drop(take duplicate)
    }
    0
}
