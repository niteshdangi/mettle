import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.boxed
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
    let fail_allocator = Probe(core.ptr.from_mut(failed))
    match capture boxed.try_new_uninit_slice_in<i32, Probe>(
        3usize,
        fail_allocator.clone()
    ) {
        success(_) => { return 1 },
        failure(error) => {
            if error.size != 12usize || error.align != 4usize { return 2 }
        }
    }
    match capture boxed.try_new_zeroed_slice_in<i32, Probe>(
        3usize,
        fail_allocator.clone()
    ) {
        success(_) => { return 3 },
        failure(error) => {
            if error.size != 12usize || error.align != 4usize { return 4 }
        }
    }
    match capture boxed.try_new_uninit_slice_in<i32, Probe>(
        0xffffffffffffffffusize,
        fail_allocator.clone()
    ) {
        success(_) => { return 9 },
        failure(error) => {
            if error.align != 4usize { return 10 }
        }
    }
    if failed.attempts != 2 || failed.live != 0 || failed.frees != 0 {
        return 5
    }

    var successful = Record(0, 0, 0, 0, 0usize, 0usize, false)
    {
        let owner = try boxed.try_new_zeroed_slice_in<u32, Probe>(
            3usize,
            Probe(core.ptr.from_mut(successful))
        )
        if owner.get().len() != 3usize || successful.size != 12usize ||
            successful.align != 4usize || successful.live != 1 {
            return 6
        }
        let initialized = unsafe { owner.assume_init() }
        if initialized.get()[0usize] != 0u32 || initialized.get()[2usize] != 0u32 {
            return 7
        }
    }
    if successful.frees != 1 || successful.live != 0 ||
        successful.mismatches != 0 {
        return 8
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
