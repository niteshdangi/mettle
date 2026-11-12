import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.{arc, boxed, rc}
import alloc.boxed.Box
import core.clone.Clone
import core.convert.From
import std.panic.{catch_panic, CatchResult}

type Record {
    panic_clone: bool
    panic_deallocate: bool
    panic_allocate: bool
    payload_drops: i32
    allocator_drops: i32
    frees: i32
}

type Payload {
    record: ptr<mut Record>
    drop { unsafe { (*self.record).payload_drops += 1 } }
}

type Probe {
    record: ptr<mut Record>
    drop { unsafe { (*self.record).allocator_drops += 1 } }
}

extend Probe implements Clone {
    fn clone(): Probe {
        if unsafe { (*self.record).panic_clone } {
            core.panic.panic("allocator clone")
        }
        Probe(self.record)
    }
}

unsafe extend Probe implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { (*self.record).panic_allocate } {
            core.panic.panic("allocator allocation")
        }
        var global = Global()
        try global.allocate(layout)
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        let should_panic = unsafe { (*self.record).panic_deallocate }
        unsafe {
            (*self.record).panic_deallocate = false
            var global = Global()
            global.deallocate(pointer, layout)
            (*self.record).frees += 1
        }
        if should_panic { core.panic.panic("allocator deallocation") }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(size, old.align())
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(size, old.align())
    }
}

fn main(): i32 {
    var extracted = Record(false, true, false, 0, 0, 0)
    {
        let pointer = core.ptr.from_mut(extracted)
        let owner = boxed.new_in(Payload(pointer), Probe(pointer))
        match take catch_panic(take fn(): Unit {
            let _ = owner.into_inner()
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 1 }
        }
    }
    if extracted.payload_drops != 1 || extracted.allocator_drops != 1 ||
        extracted.frees != 1 {
        return 2
    }

    var upgraded = Record(false, false, false, 0, 0, 0)
    {
        let pointer = core.ptr.from_mut(upgraded)
        let owner = rc.new_in(Payload(pointer), Probe(pointer))
        let weak_owner = owner.downgrade()
        upgraded.panic_clone = true
        match take catch_panic(fn(): Unit {
            let _ = weak_owner.upgrade()
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 3 }
        }
        if owner.strong_count() != 1usize { return 4 }
        upgraded.panic_clone = false
        core.mem.drop(take owner)
        if weak_owner.upgrade().is_present() || upgraded.payload_drops != 1 { return 5 }
        core.mem.drop(take weak_owner)
    }
    if upgraded.payload_drops != 1 || upgraded.allocator_drops != 2 ||
        upgraded.frees != 1 {
        return 6
    }

    var refused = Record(false, false, false, 0, 0, 0)
    {
        let pointer = core.ptr.from_mut(refused)
        let source = boxed.new_in(Payload(pointer), Probe(pointer))
        refused.panic_allocate = true
        match take catch_panic(take fn(): Unit {
            let _ = rc.Rc<Payload, Probe>.(From<Box<Payload, Probe>>).from(source)
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 7 }
        }
    }
    if refused.payload_drops != 1 || refused.allocator_drops != 1 ||
        refused.frees != 1 { return 8 }

    var moved = Record(false, false, false, 0, 0, 0)
    {
        let pointer = core.ptr.from_mut(moved)
        let source = boxed.new_in(Payload(pointer), Probe(pointer))
        moved.panic_deallocate = true
        match take catch_panic(take fn(): Unit {
            let _ = arc.Arc<Payload, Probe>.(From<Box<Payload, Probe>>).from(source)
        }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 9 }
        }
    }
    if moved.payload_drops != 1 || moved.allocator_drops != 1 ||
        moved.frees != 2 { return 10 }
    0
}
