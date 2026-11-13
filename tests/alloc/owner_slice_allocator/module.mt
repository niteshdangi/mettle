import alloc.alloc.{Allocator, Global, Layout, AllocError}

pub type Record {
    pub attempts: i32
    pub frees: i32
    pub live: i32
    pub mismatches: i32
    pub size: usize
    pub align: usize
    pub fail: bool
}

pub copy type Probe { pub record: ptr<mut Record> }

// Probe is confined to the scope of its live Record.
extend Probe implements core.clone.Clone {
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
