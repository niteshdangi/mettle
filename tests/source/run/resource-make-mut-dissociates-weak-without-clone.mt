import alloc.{arc, rc}
import core.clone.Clone

type Payload {
    value: i32
    clones: ptr<mut i32>
    drops: ptr<mut i32>
    drop { unsafe { *self.drops += 1 } }
}
extend Payload implements Clone {
    fn clone(): Payload {
        unsafe { *self.clones += 1 }
        Payload(self.value, self.clones, self.drops)
    }
}

fn main(): i32 {
    var local_clones = 0
    var local_drops = 0
    {
        var owner = rc.new(Payload(
            7, core.ptr.from_mut(local_clones), core.ptr.from_mut(local_drops)
        ))
        let weak_handle = owner.downgrade()
        owner.make_mut().value = 11
        if local_clones != 0 || weak_handle.upgrade().is_present() ||
            owner.get().value != 11 || local_drops != 0 {
            return 1
        }
        let sibling = owner.retain()
        owner.make_mut().value = 13
        if local_clones != 1 || sibling.get().value != 11 ||
            owner.get().value != 13 {
            return 2
        }
    }
    if local_drops != 2 { return 3 }

    var atomic_clones = 0
    var atomic_drops = 0
    {
        var owner = arc.new(Payload(
            17, core.ptr.from_mut(atomic_clones), core.ptr.from_mut(atomic_drops)
        ))
        let weak_handle = owner.downgrade()
        owner.make_mut().value = 19
        if atomic_clones != 0 || weak_handle.upgrade().is_present() ||
            owner.get().value != 19 || atomic_drops != 0 {
            return 4
        }
        let sibling = owner.retain()
        owner.make_mut().value = 23
        if atomic_clones != 1 || sibling.get().value != 19 ||
            owner.get().value != 23 {
            return 5
        }
    }
    if atomic_drops != 2 { return 6 }
    0
}
