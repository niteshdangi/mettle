import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.boxed
import alloc.rc
import alloc.arc
import alloc.vec

type Record {
    allocations: i32
    deallocations: i32
    grows: i32
    shrinks: i32
    mismatches: i32
    size: usize
    alignment: usize
    fail_grow: bool
}

copy type AuditedAllocator { record: ptr<mut Record> }

extend AuditedAllocator implements core.clone.Clone {
    fn clone(): AuditedAllocator { AuditedAllocator(self.record) }
}

unsafe extend AuditedAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.record).allocations += 1
            (*self.record).size = layout.size()
            (*self.record).alignment = layout.align()
        }
        var global = Global()
        try global.allocate(layout)
    }

    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if (*self.record).size != layout.size() ||
                (*self.record).alignment != layout.align() {
                (*self.record).mismatches += 1
            }
            (*self.record).deallocations += 1
        }
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }

    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        let fail = unsafe { (*self.record).fail_grow }
        unsafe {
            if (*self.record).size != old.size() ||
                (*self.record).alignment != old.align() {
                (*self.record).mismatches += 1
            }
            (*self.record).grows += 1
        }
        if fail { throw AllocError(new_size, old.align()) }
        var global = Global()
        let grown = unsafe { try global.grow(pointer, old, new_size) }
        unsafe { (*self.record).size = new_size }
        grown
    }

    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        unsafe {
            if (*self.record).size != old.size() ||
                (*self.record).alignment != old.align() {
                (*self.record).mismatches += 1
            }
            (*self.record).shrinks += 1
        }
        var global = Global()
        let shrunk = unsafe { try global.shrink(pointer, old, new_size) }
        unsafe { (*self.record).size = new_size }
        shrunk
    }
}

fn main(): i32 {
    var box_record = Record(0, 0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = boxed.new_in(
            41,
            AuditedAllocator(core.ptr.from_mut(box_record))
        )
        if *owner.get() != 41 { return 1 }
    }
    if box_record.allocations != 1 || box_record.deallocations != 1 ||
        box_record.mismatches != 0 { return 2 }

    var rc_record = Record(0, 0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = rc.new_in(
            42,
            AuditedAllocator(core.ptr.from_mut(rc_record))
        )
        if *owner.get() != 42 { return 3 }
    }
    if rc_record.allocations != 1 || rc_record.deallocations != 1 ||
        rc_record.mismatches != 0 { return 4 }

    var arc_record = Record(0, 0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = arc.new_in(
            43,
            AuditedAllocator(core.ptr.from_mut(arc_record))
        )
        if *owner.get() != 43 { return 5 }
    }
    if arc_record.allocations != 1 || arc_record.deallocations != 1 ||
        arc_record.mismatches != 0 { return 6 }

    var vec_record = Record(0, 0, 0, 0, 0, 0usize, 0usize, false)
    let vec_record_ptr = core.ptr.from_mut(vec_record)
    {
        var values = vec.new_in<i32, AuditedAllocator>(
            AuditedAllocator(vec_record_ptr)
        )
        values.push(17)
        values.push(29)
        unsafe { (*vec_record_ptr).fail_grow = true }
        match capture values.try_reserve(10000usize) {
            success(_) => { return 7 },
            failure(_) => {}
        }
        if values.len() != 2usize || values[0usize] != 17 ||
            values[1usize] != 29 { return 8 }
        unsafe { (*vec_record_ptr).fail_grow = false }
        match capture values.try_reserve(10000usize) {
            success(_) => {},
            failure(_) => { return 9 }
        }
        if values[0usize] != 17 || values[1usize] != 29 { return 10 }
        values.shrink_to_fit()
        if values.len() != 2usize || values[0usize] != 17 ||
            values[1usize] != 29 { return 11 }
    }
    if vec_record.allocations != 1 || vec_record.deallocations != 1 ||
        vec_record.grows != 2 || vec_record.shrinks != 1 ||
        vec_record.mismatches != 0 { return 12 }
    0
}
