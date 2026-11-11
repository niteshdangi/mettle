import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.arc
import alloc.rc
import core.clone.Clone

type Record {
    attempts: i32
    frees: i32
    live: i32
    mismatches: i32
    size: usize
    align: usize
    fail: bool
}

copy type Probe { record: ptr<mut Record> }

// Probe is confined to the scope of its live Record.
extend Probe implements package.core.clone.Clone {
    fn clone(): Probe { Probe(self.record) }
}

unsafe extend Probe implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        unsafe {
            (*self.record).attempts += 1
            if (*self.record).fail {
                throw AllocError(layout.size(), layout.align())
            }
        }
        var global = Global()
        let pointer = try global.allocate(layout)
        if layout.size() != 0usize {
            unsafe {
                (*self.record).size = layout.size()
                (*self.record).align = layout.align()
                (*self.record).live += 1
            }
        }
        pointer
    }

    mut unsafe fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            if (*self.record).size != layout.size() ||
                (*self.record).align != layout.align() {
                (*self.record).mismatches += 1
            }
            if layout.size() != 0usize { (*self.record).live -= 1 }
            (*self.record).frees += 1
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

fn run(): i32 throws AllocError {
    var failed = Record(0, 0, 0, 0, 0usize, 0usize, true)
    let allocator = Probe(core.ptr.from_mut(failed))
    match capture rc.try_new_uninit_slice_in<i32, Probe>(3usize, allocator.clone()) {
        success(_) => { return 1 },
        failure(_) => {}
    }
    match capture arc.try_new_zeroed_slice_in<i32, Probe>(3usize, allocator.clone()) {
        success(_) => { return 2 },
        failure(_) => {}
    }
    match capture rc.try_new_uninit_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        allocator.clone()
    ) {
        success(_) => { return 3 },
        failure(_) => {}
    }
    match capture arc.try_new_zeroed_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        allocator.clone()
    ) {
        success(_) => { return 10 },
        failure(_) => {}
    }
    if failed.attempts != 2 || failed.live != 0 || failed.frees != 0 {
        return 4
    }

    var local_record = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try rc.try_new_uninit_slice_in<u32, Probe>(
            2usize,
            Probe(core.ptr.from_mut(local_record))
        )
        if owner.get().len() != 2usize || local_record.live != 1 { return 5 }
    }
    if local_record.frees != 1 || local_record.live != 0 || local_record.mismatches != 0 {
        return 6
    }

    var atomic = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try arc.try_new_zeroed_slice_in<u32, Probe>(
            2usize,
            Probe(core.ptr.from_mut(atomic))
        )
        if owner.get().len() != 2usize || atomic.live != 1 { return 7 }
        let initialized = unsafe { owner.assume_init() }
        if initialized.get()[0usize] != 0u32 || initialized.get()[1usize] != 0u32 {
            return 8
        }
    }
    if atomic.frees != 1 || atomic.live != 0 || atomic.mismatches != 0 {
        return 9
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
