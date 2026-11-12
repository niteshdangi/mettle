import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.boxed
import core.clone.Clone
import std.panic.{catch_panic, CatchResult}

type Record {
    allocations: i32
    frees: i32
    payload_drops: i32
    allocator_drops: i32
    clones: i32
    panic_payload: bool
    panic_allocator: bool
    panic_allocate: bool
}

@align(64)
type Payload {
    record: ptr<mut Record>
    value: i32
    drop { unsafe { (*self.record).payload_drops += 1 } }
}
extend Payload implements Clone {
    fn clone(): Payload {
        if unsafe { (*self.record).panic_payload } { core.panic.panic("payload clone") }
        unsafe { (*self.record).clones += 1 }
        Payload(self.record, self.value)
    }
}
type Probe {
    record: ptr<mut Record>
    drop { unsafe { (*self.record).allocator_drops += 1 } }
}
extend Probe implements Clone {
    fn clone(): Probe {
        if unsafe { (*self.record).panic_allocator } { core.panic.panic("allocator clone") }
        Probe(self.record)
    }
}
unsafe extend Probe implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        if unsafe { (*self.record).panic_allocate } { core.panic.panic("allocation") }
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe { (*self.record).allocations += 1 }
        pointer
    }
    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        var global = Global()
        unsafe {
            global.deallocate(pointer, layout)
            (*self.record).frees += 1
        }
    }
    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(size, old.align())
    }
    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(size, old.align())
    }
}

fn main(): i32 {
    var record = Record(0, 0, 0, 0, 0, false, false, false)
    let counter = core.ptr.from_mut(record)
    {
        let owner = boxed.new_in(Payload(counter, 17), Probe(counter)).into_pinned()
        let original = core.ptr.from_ref(owner.get_ref())
        {
            let duplicate = owner.clone()
            let copied = core.ptr.from_ref(duplicate.get_ref())
            assert(original != copied && copied.addr() % 64usize == 0usize &&
                duplicate.get_ref().value == 17 && owner.get_ref().value == 17,
                "cloned pinned Box owns a distinct aligned allocation")
            let moved_handle = duplicate
            assert(core.ptr.from_ref(moved_handle.get_ref()) == copied, "moving the pin handle does not move its cloned payload")
        }
        assert(record.allocations == 2 && record.frees == 1 && record.payload_drops == 1,
            "successful cloned owner destroys its own payload once")
        record.panic_payload = true
        match take catch_panic(fn(): Unit { let _ = owner.clone() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 1 }
        }
        record.panic_payload = false
        record.panic_allocator = true
        match take catch_panic(fn(): Unit { let _ = owner.clone() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 2 }
        }
        record.panic_allocator = false
        record.panic_allocate = true
        match take catch_panic(fn(): Unit { let _ = owner.clone() }) {
            CatchResult.Panicked(_) => {},
            CatchResult.Returned(_) => { return 3 }
        }
        record.panic_allocate = false
        assert(core.ptr.from_ref(owner.get_ref()) == original && owner.get_ref().value == 17 &&
            record.allocations == 2 && record.frees == 1 && record.payload_drops == 3 &&
            record.allocator_drops == 2, "clone unwind cleans only completed temporaries and preserves the original pin")
    }
    assert(record.allocations == record.frees && record.payload_drops == 4 &&
        record.allocator_drops == 3 && record.clones == 3, "all cloned resources are destroyed exactly once")
    0
}
