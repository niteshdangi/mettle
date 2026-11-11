import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.boxed
import alloc.string

type Record {
    allocations: i32
    deallocations: i32
    live: i32
    mismatches: i32
    size0: usize
    alignment0: usize
    active0: bool
    size1: usize
    alignment1: usize
    active1: bool
    fail: bool
}

copy type AuditedAllocator { record: ptr<mut Record> }

// Each allocator is used only while its Record remains live.
extend AuditedAllocator implements package.core.clone.Clone {
    fn clone(): AuditedAllocator { AuditedAllocator(self.record) }
}

unsafe extend AuditedAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.record).allocations += 1
            if (*self.record).fail {
                throw AllocError(layout.size(), layout.align())
            }
        }
        var global = Global()
        let pointer = try global.allocate(layout)
        if layout.size() != 0usize {
            unsafe {
                if !(*self.record).active0 {
                    (*self.record).size0 = layout.size()
                    (*self.record).alignment0 = layout.align()
                    (*self.record).active0 = true
                } else {
                    (*self.record).size1 = layout.size()
                    (*self.record).alignment1 = layout.align()
                    (*self.record).active1 = true
                }
                (*self.record).live += 1
            }
        }
        pointer
    }

    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if layout.size() != 0usize {
                if (*self.record).active0 &&
                    (*self.record).size0 == layout.size() &&
                    (*self.record).alignment0 == layout.align() {
                    (*self.record).active0 = false
                } else if (*self.record).active1 &&
                    (*self.record).size1 == layout.size() &&
                    (*self.record).alignment1 == layout.align() {
                    (*self.record).active1 = false
                } else {
                    (*self.record).mismatches += 1
                }
                (*self.record).live -= 1
            }
            (*self.record).deallocations += 1
        }
        var global = Global()
        unsafe { global.deallocate(pointer, layout) }
    }

    mut unsafe fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut unsafe fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

fn main(): i32 {
    var copied_record = Record(
        0, 0, 0, 0, 0usize, 0usize, false, 0usize, 0usize, false, false
    )
    {
        let owner = boxed.copy_text_in(
            "h\u{e9}",
            AuditedAllocator(core.ptr.from_mut(copied_record))
        )
        if owner.get() != "h\u{e9}" || copied_record.allocations != 1 ||
            copied_record.size0 != 3usize || copied_record.alignment0 != 1usize {
            return 1
        }
    }
    if copied_record.deallocations != 1 || copied_record.live != 0 ||
        copied_record.mismatches != 0 {
        return 2
    }

    var empty_record = Record(
        0, 0, 0, 0, 0usize, 0usize, false, 0usize, 0usize, false, false
    )
    {
        let owner = boxed.copy_text_in(
            "",
            AuditedAllocator(core.ptr.from_mut(empty_record))
        )
        if owner.get().len() != 0usize { return 9 }
    }
    if empty_record.allocations != 1 || empty_record.deallocations != 0 ||
        empty_record.live != 0 {
        return 10
    }

    var moved_record = Record(
        0, 0, 0, 0, 0usize, 0usize, false, 0usize, 0usize, false, false
    )
    {
        var source = string.with_capacity_in(
            16usize,
            AuditedAllocator(core.ptr.from_mut(moved_record))
        )
        source.push_str("owned")
        if source.capacity() < 16usize { return 3 }
        let owner = boxed.from_string(take source)
        if owner.get() != "owned" || moved_record.live != 1 ||
            moved_record.mismatches != 0 {
            return 4
        }
    }
    if moved_record.deallocations != moved_record.allocations ||
        moved_record.live != 0 ||
        moved_record.mismatches != 0 {
        return 5
    }

    var failed_record = Record(
        0, 0, 0, 0, 0usize, 0usize, false, 0usize, 0usize, false, true
    )
    match capture boxed.try_copy_text_in(
        "failure",
        AuditedAllocator(core.ptr.from_mut(failed_record))
    ) {
        success(_) => { return 6 },
        failure(error) => {
            if error.size != 7usize || error.align != 1usize { return 7 }
        }
    }
    if failed_record.allocations != 1 || failed_record.deallocations != 0 ||
        failed_record.live != 0 {
        return 8
    }
    0
}
