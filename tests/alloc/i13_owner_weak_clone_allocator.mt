import alloc.alloc.{ Allocator, Global, Layout, AllocError }
import alloc.arc
import alloc.rc
import core.clone.Clone

type Record {
    allocations: i32
    deallocations: i32
    live: i32
    mismatches: i32
    size: usize
    alignment: usize
    payload_drops: i32
}

// Both allocator and payload counters outlive every strong and weak handle.
type Payload {
    record: ptr<mut Record>
    drop { unsafe { (*self.record).payload_drops += 1 } }
}

copy type Probe { record: ptr<mut Record> }

extend Probe implements Clone {
    fn clone(): Probe { Probe(self.record) }
}

extend Probe implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe {
            (*self.record).allocations += 1
            (*self.record).live += 1
            (*self.record).size = layout.size()
            (*self.record).alignment = layout.align()
        }
        pointer
    }

    mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if (*self.record).size != layout.size() ||
                (*self.record).alignment != layout.align() {
                (*self.record).mismatches += 1
            }
            (*self.record).deallocations += 1
            (*self.record).live -= 1
        }
        var global = Global()
        global.deallocate(pointer, layout)
    }

    mut fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut fn shrink(pointer: ptr<mut u8>, old: Layout,
        new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

fn main(): i32 {
    var local_state = Record(0, 0, 0, 0, 0usize, 0usize, 0)
    let local_record = core.ptr.from_mut(local_state)
    {
        let owner = rc.new_in(Payload(local_record), Probe(local_record))
        let observer = owner.downgrade()
        let duplicate = observer.clone()
        if owner.weak_count() != 2usize || local_state.allocations != 1 ||
            local_state.live != 1 {
            return 1
        }
        core.mem.drop(take owner)
        if local_state.deallocations != 0 || local_state.live != 1 ||
            observer.strong_count() != 0usize || local_state.payload_drops != 1 {
            return 2
        }
        core.mem.drop(take observer)
        if local_state.deallocations != 0 || duplicate.weak_count() != 0usize {
            return 3
        }
        let expired = duplicate.clone()
        if expired.strong_count() != 0usize || expired.weak_count() != 0usize ||
            expired.upgrade().is_present() {
            return 9
        }
        core.mem.drop(take duplicate)
        if local_state.deallocations != 0 { return 10 }
        core.mem.drop(take expired)
    }
    if local_state.allocations != 1 || local_state.deallocations != 1 ||
        local_state.live != 0 || local_state.mismatches != 0 ||
        local_state.payload_drops != 1 {
        return 4
    }

    var atomic = Record(0, 0, 0, 0, 0usize, 0usize, 0)
    let atomic_record = core.ptr.from_mut(atomic)
    {
        let owner = arc.new_in(Payload(atomic_record), Probe(atomic_record))
        let observer = owner.downgrade()
        let duplicate = observer.clone()
        if owner.weak_count() != 2usize || atomic.allocations != 1 ||
            atomic.live != 1 {
            return 5
        }
        core.mem.drop(take owner)
        if atomic.deallocations != 0 || atomic.live != 1 ||
            observer.strong_count() != 0usize || atomic.payload_drops != 1 {
            return 6
        }
        core.mem.drop(take observer)
        if atomic.deallocations != 0 || duplicate.weak_count() != 0usize {
            return 7
        }
        let expired = duplicate.clone()
        if expired.strong_count() != 0usize || expired.weak_count() != 0usize ||
            expired.upgrade().is_present() {
            return 11
        }
        core.mem.drop(take duplicate)
        if atomic.deallocations != 0 { return 12 }
        core.mem.drop(take expired)
    }
    if atomic.allocations != 1 || atomic.deallocations != 1 ||
        atomic.live != 0 || atomic.mismatches != 0 || atomic.payload_drops != 1 {
        return 8
    }
    0
}
