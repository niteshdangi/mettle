import alloc.alloc.{Allocator, Global, Layout, AllocError}
import alloc.boxed

type Record {
    allocations: i32
    deallocations: i32
    mismatches: i32
    live: i32
    identity: u32
    size: usize
    align: usize
}

type TaggedAllocator { record: ptr<mut Record>; identity: u32 }

extend TaggedAllocator implements Allocator {
    mut fn allocate(layout: Layout): ptr<mut u8> throws AllocError {
        var global = Global()
        let pointer = try global.allocate(layout)
        unsafe {
            (*self.record).allocations += 1
            if layout.size() != 0usize {
                (*self.record).live += 1
                (*self.record).size = layout.size()
                (*self.record).align = layout.align()
            }
        }
        pointer
    }

    mut fn deallocate(pointer: ptr<mut u8>, layout: Layout): Unit {
        unsafe {
            (*self.record).deallocations += 1
            if self.identity != (*self.record).identity ||
                layout.size() != (*self.record).size ||
                layout.align() != (*self.record).align {
                (*self.record).mismatches += 1
            }
            if layout.size() != 0usize { (*self.record).live -= 1 }
        }
        var global = Global()
        global.deallocate(pointer, layout)
    }

    mut fn grow(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }

    mut fn shrink(pointer: ptr<mut u8>, old: Layout, new_size: usize): ptr<mut u8> throws AllocError {
        throw AllocError(new_size, old.align())
    }
}

fn run(): i32 throws AllocError {
    var record = Record(0, 0, 0, 0, 91u32, 0usize, 0usize)
    var sum = 0i32
    {
        let owner = boxed.new_in(
            [11i32, 13i32, 17i32],
            TaggedAllocator(core.ptr.from_mut(record), 91u32)
        )
        for value in take owner {
            sum += value
            break
        }
    }
    if sum != 11i32 || record.allocations != 1 || record.deallocations != 1 ||
        record.mismatches != 0 || record.live != 0 ||
        record.size != 3usize * core.mem.size_of<i32>() {
        return 1
    }
    0
}

fn main(): i32 {
    match take capture run() {
        success(code) => code,
        failure(_) => 100
    }
}
