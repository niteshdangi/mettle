import alloc.arc
import alloc.rc

// The counters outlive their owners and are touched only by Drop.
type Tracked {
    drops: ptr<mut i32>
    value: i32
    drop { unsafe { *self.drops += 1 } }
}

fn main(): i32 {
    var local_drops = 0
    {
        let owner = rc.new(Tracked(core.ptr.from_mut(local_drops), 17))
        let sibling = owner.retain()
        let observer = owner.downgrade()
        match take owner.into_inner() {
            none => {},
            present(_) => { return 1 }
        }
        if local_drops != 0 { return 2 }
        match take sibling.into_inner() {
            present(value) => { if value.value != 17 { return 3 } },
            none => { return 4 }
        }
        if local_drops != 1 || observer.strong_count() != 0usize ||
            observer.weak_count() != 0usize || observer.upgrade().is_present() {
            return 5
        }
    }
    if local_drops != 1 { return 6 }

    var atomic_drops = 0
    {
        let owner = arc.new(Tracked(core.ptr.from_mut(atomic_drops), 29))
        let sibling = owner.retain()
        let observer = owner.downgrade()
        match take owner.into_inner() {
            none => {},
            present(_) => { return 7 }
        }
        if atomic_drops != 0 { return 8 }
        match take sibling.into_inner() {
            present(value) => { if value.value != 29 { return 9 } },
            none => { return 10 }
        }
        if atomic_drops != 1 || observer.strong_count() != 0usize ||
            observer.weak_count() != 0usize || observer.upgrade().is_present() {
            return 11
        }
    }
    if atomic_drops != 1 { return 12 }
    0
}
